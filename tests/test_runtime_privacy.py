"""Synthetic privacy contracts for Trellis runtime/context handling.

These tests are intentionally runnable against a pristine base snapshot.  The
first red run is recorded before implementation; the same file is the privacy
gate after the fix.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import tempfile
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".trellis" / "scripts"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_common(name: str, path: Path):
    # The common package uses relative imports; import through its package
    # path exactly as task.py does.
    import sys

    sys.path.insert(0, str(SCRIPTS))
    return __import__(f"common.{name}", fromlist=["*"])


def test_context_paths_are_canonically_contained(tmp_path: Path) -> None:
    task_context = _load_common("task_context", SCRIPTS / "common" / "task_context.py")
    repo = tmp_path / "repo"
    repo.mkdir()
    safe = repo / "docs" / "safe.md"
    safe.parent.mkdir()
    safe.write_text("SAFE", encoding="utf-8")
    outside = tmp_path / "outside.md"
    outside.write_text("PRIVATE-OUTSIDE", encoding="utf-8")
    (repo / "escape.md").symlink_to(outside)

    assert task_context._resolve_context_entry_path("docs/safe.md", repo, None) == safe.resolve()
    assert task_context._resolve_context_entry_path(str(outside), repo, None) is None
    assert task_context._resolve_context_entry_path("../outside.md", repo, None) is None
    assert task_context._resolve_context_entry_path("escape.md", repo, None) is None


def test_active_task_rejects_tampered_runtime_task_refs(tmp_path: Path) -> None:
    """A legacy session JSON must not turn current_task into an escape path."""
    active = _load_common("active_task", SCRIPTS / "common" / "active_task.py")
    repo = tmp_path / "repo"
    tasks = repo / ".trellis" / "tasks"
    safe = tasks / "safe"
    safe.mkdir(parents=True)
    outside = tmp_path / "outside-task"
    outside.mkdir()
    (tasks / "link").symlink_to(outside, target_is_directory=True)

    key = active._context_key("codex", "session", "fixture-session")
    context_path = active._context_path(repo, key)
    context_path.parent.mkdir(parents=True)
    for current_task in (str(outside), "../outside-task", ".trellis/tasks/link"):
        context_path.write_text(
            json.dumps({"platform": "codex", "current_task": current_task}),
            encoding="utf-8",
        )
        resolved = active.resolve_active_task(
            repo,
            {"session_id": "fixture-session"},
            platform="codex",
            allow_single_session_fallback=False,
            allow_environment_context=False,
        )
        assert resolved.task_path is None
        assert resolved.stale


def test_hook_reader_does_not_read_escape(tmp_path: Path) -> None:
    hook = _load("inject_subagent_context", ROOT / ".codex" / "hooks" / "inject-subagent-context.py")
    repo = tmp_path / "repo"
    repo.mkdir()
    outside = tmp_path / "outside.md"
    outside.write_text("PRIVATE-OUTSIDE", encoding="utf-8")
    (repo / "escape.md").symlink_to(outside)
    (repo / "safe.md").write_text("SAFE", encoding="utf-8")

    assert hook._read_file_bytes(str(repo), "safe.md") == b"SAFE"
    assert hook._read_file_bytes(str(repo), str(outside)) is None
    assert hook._read_file_bytes(str(repo), "../outside.md") is None
    assert hook._read_file_bytes(str(repo), "escape.md") is None


def test_hook_rejects_external_manifest_and_task_dir(tmp_path: Path) -> None:
    """Manifest JSONL itself, not only its child entries, is untrusted."""
    hook = _load("inject_subagent_context_manifest", ROOT / ".codex" / "hooks" / "inject-subagent-context.py")
    repo = tmp_path / "repo"
    repo.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "outside.md").write_text("PRIVATE-OUTSIDE", encoding="utf-8")
    (outside / "implement.jsonl").write_text(
        json.dumps({"file": str(outside / "outside.md"), "reason": "fixture"}) + "\n",
        encoding="utf-8",
    )
    (repo / "task-link").symlink_to(outside, target_is_directory=True)

    for manifest in (str(outside / "implement.jsonl"), "../outside/implement.jsonl", "task-link/implement.jsonl"):
        assert hook.read_jsonl_entries(str(repo), manifest) == []


def test_runtime_ticket_context_key_cannot_escape_read_write_delete(tmp_path: Path) -> None:
    """Ticket keys and runtime directories are untrusted sink inputs."""
    active = _load_common("active_task", SCRIPTS / "common" / "active_task.py")
    repo = tmp_path / "repo"
    task = repo / ".trellis" / "tasks" / "safe"
    task.mkdir(parents=True)
    outside = tmp_path / "outside.json"
    outside.write_text(json.dumps({"platform": "codex", "current_task": ".trellis/tasks/safe"}), encoding="utf-8")

    # A shell ticket is the only route that can supply a raw context_key to the
    # resolver.  Make its current command and cwd valid so only key validation
    # distinguishes this from a real ticket.
    runtime = repo / ".trellis" / ".runtime"
    tickets = runtime / "shell-tickets"
    tickets.mkdir(parents=True)
    ticket = tickets / "fixture.json"
    ticket.write_text(
        json.dumps({
            "context_key": "../../../../outside",
            "cwd": str(repo),
            "created_at_epoch": 2_000_000_000,
            "subcommands": [{"name": "current"}],
        }),
        encoding="utf-8",
    )

    old_argv = active.sys.argv
    old_cwd = Path.cwd()
    active.sys.argv = ["task.py", "current"]
    try:
        os.chdir(repo)
        resolved = active.resolve_active_task(
            repo, {}, platform="unknown", allow_single_session_fallback=False,
        )
        read_ok = resolved.task_path is None

        before = outside.read_bytes()
        write_result = active.set_active_task(".trellis/tasks/safe", repo, {}, platform="unknown")
        write_ok = write_result is None and outside.read_bytes() == before

        outside.write_bytes(before)
        clear_result = active.clear_active_task(repo, {}, platform="unknown")
        delete_ok = clear_result.task_path is None and outside.exists()
    finally:
        active.sys.argv = old_argv
        os.chdir(old_cwd)

    # Valid opaque keys remain compatible and stay below the canonical session
    # directory; separators, absolute forms and traversal are rejected.
    valid = active._context_key("codex", "session", "fixture-session")
    valid_path = active._context_path(repo, valid)
    assert valid_path is not None
    assert valid_path.resolve().is_relative_to(repo.resolve())
    bad_keys_ok = all(
        active._context_path(repo, bad) is None
        for bad in ("/tmp/absolute", "../../outside", "codex/session/hash", "codex_session_../../outside")
    )

    # A symlinked sessions or shell-ticket directory must fail closed rather
    # than redirecting reads/deletes to an external fixture directory.
    ticket.unlink()
    tickets.rmdir()
    sessions = runtime / "sessions"
    if sessions.exists():
        sessions.rmdir()
    sessions_target = tmp_path / "sessions-outside"
    sessions_target.mkdir()
    sessions.symlink_to(sessions_target, target_is_directory=True)
    symlink_dir_ok = active._runtime_sessions_dir(repo) is None
    symlink_read_ok = active.resolve_active_task(
        repo, {"session_id": "fixture-session"}, platform="codex",
        allow_single_session_fallback=False, allow_environment_context=False,
    ).task_path is None
    shell_target = tmp_path / "shell-tickets-outside"
    shell_target.mkdir()
    shell_link = runtime / "shell-tickets"
    shell_link.symlink_to(shell_target, target_is_directory=True)
    shell_dirs = active._shell_ticket_dirs(repo)
    shell_symlink_ok = shell_link not in shell_dirs
    assert read_ok and write_ok and delete_ok and bad_keys_ok and symlink_dir_ok and symlink_read_ok and shell_symlink_ok, {
        "read": read_ok,
        "write": write_ok,
        "delete": delete_ok,
        "bad_keys": bad_keys_ok,
        "sessions_symlink": symlink_dir_ok,
        "sessions_read": symlink_read_ok,
        "shell_tickets_symlink": shell_symlink_ok,
    }


def test_single_session_fallback_requires_opaque_regular_context(tmp_path: Path) -> None:
    """Fallback must not expose an untrusted filename stem as context identity."""
    active = _load_common("active_task", SCRIPTS / "common" / "active_task.py")
    repo = tmp_path / "repo"
    task = repo / ".trellis" / "tasks" / "safe"
    task.mkdir(parents=True)
    sessions = repo / ".trellis" / ".runtime" / "sessions"
    sessions.mkdir(parents=True)

    def write_session(stem: str) -> Path:
        path = sessions / f"{stem}.json"
        path.write_text(json.dumps({"current_task": ".trellis/tasks/safe"}), encoding="utf-8")
        return path

    def fallback_for(stem: str):
        path = write_session(stem)
        try:
            return active._resolve_single_session_fallback(repo)
        finally:
            if path.is_file() or path.is_symlink():
                path.unlink()

    # Legacy/raw session, conversation and transcript-style stems are not
    # opaque even though the filename itself is safely contained.
    raw_stems = (
        "fixture-session-id",
        "codex_session_legacy-id",
        "codex_conversation_legacy-id",
        "legacy-transcript-id",
    )
    raw_results = {stem: fallback_for(stem) for stem in raw_stems}

    # Explicit opaque fixture keys remain compatible with fallback.
    opaque_stems = ("ctx-" + "a" * 24, "anon-" + "b" * 24)
    opaque_results = {stem: fallback_for(stem) for stem in opaque_stems}

    # A symlink or non-regular JSON file must not be opened or exposed as the
    # fallback context, even when its stem is otherwise opaque.
    symlink_stem = "ctx-" + "c" * 24
    symlink_path = sessions / f"{symlink_stem}.json"
    outside = tmp_path / "outside-session.json"
    outside.write_text(json.dumps({"current_task": ".trellis/tasks/safe"}), encoding="utf-8")
    symlink_path.symlink_to(outside)
    symlink_result = active._resolve_single_session_fallback(repo)
    symlink_path.unlink()

    directory_stem = "anon-" + "d" * 24
    directory_path = sessions / f"{directory_stem}.json"
    directory_path.mkdir()
    directory_result = active._resolve_single_session_fallback(repo)

    assert all(result is None for result in raw_results.values()), raw_results
    assert all(
        result is not None
        and result.source_type == "session-fallback"
        and result.context_key == stem
        and result.task_path == ".trellis/tasks/safe"
        for stem, result in opaque_results.items()
    ), opaque_results
    assert symlink_result is None
    assert directory_result is None


def test_task_json_symlink_is_rejected_by_loader_and_hooks(tmp_path: Path) -> None:
    """A canonical task directory must not make an external task.json trusted."""
    tasks = _load_common("tasks", SCRIPTS / "common" / "tasks.py")
    inject = _load("inject_workflow_state_task_json", ROOT / ".codex" / "hooks" / "inject-workflow-state.py")
    session_start = _load("session_start_task_json", ROOT / ".codex" / "hooks" / "session-start.py")
    repo = tmp_path / "repo"
    task_dir = repo / ".trellis" / "tasks" / "safe"
    task_dir.mkdir(parents=True)
    outside = tmp_path / "outside-task.json"
    outside.write_text(
        json.dumps({"id": "PRIVATE-ID", "title": "PRIVATE-TITLE", "status": "completed"}),
        encoding="utf-8",
    )
    (task_dir / "task.json").symlink_to(outside)

    active = SimpleNamespace(task_path=".trellis/tasks/safe", stale=False, source="fixture")
    inject._resolve_active_task = lambda _root, _input: active
    session_start._resolve_active_task = lambda _trellis_dir, _input: active

    loaded = tasks.load_task(task_dir, repo_root=repo)
    injected = inject.get_active_task(repo, {})
    status = session_start._get_task_status(repo / ".trellis", {})
    compact = session_start._build_compact_current_state(repo / ".trellis", {}, [])

    assert loaded is None
    assert injected is None
    assert "PRIVATE-ID" not in status and "PRIVATE-TITLE" not in status
    assert "PRIVATE-ID" not in compact and "PRIVATE-TITLE" not in compact


def test_task_directory_symlink_is_rejected_across_loader_hooks_and_context(tmp_path: Path, capsys) -> None:
    """A task entry itself must never redirect reads or JSONL writes outside the repo."""
    tasks = _load_common("tasks", SCRIPTS / "common" / "tasks.py")
    task_context = _load_common("task_context", SCRIPTS / "common" / "task_context.py")
    inject = _load("inject_workflow_state_task_dir", ROOT / ".codex" / "hooks" / "inject-workflow-state.py")
    session_start = _load("session_start_task_dir", ROOT / ".codex" / "hooks" / "session-start.py")
    repo = tmp_path / "repo"
    tasks_dir = repo / ".trellis" / "tasks"
    tasks_dir.mkdir(parents=True)
    (repo / "safe.md").write_text("SAFE", encoding="utf-8")
    outside = tmp_path / "outside-task-dir"
    outside.mkdir()
    (outside / "task.json").write_text(
        json.dumps({"id": "PRIVATE-ID", "title": "PRIVATE-TITLE", "status": "completed"}),
        encoding="utf-8",
    )
    (outside / "implement.jsonl").write_text(
        json.dumps({"file": "safe.md", "reason": "PRIVATE-CONTEXT"}) + "\n",
        encoding="utf-8",
    )
    evil = tasks_dir / "evil"
    evil.symlink_to(outside, target_is_directory=True)

    active = SimpleNamespace(task_path=".trellis/tasks/evil", stale=False, source="fixture")
    inject._resolve_active_task = lambda _root, _input: active
    session_start._resolve_active_task = lambda _trellis_dir, _input: active
    task_context.get_repo_root = lambda: repo

    loaded = tasks.load_task(evil, repo_root=repo)
    iterated = list(tasks.iter_active_tasks(tasks_dir))
    injected = inject.get_active_task(repo, {})
    status = session_start._get_task_status(repo / ".trellis", {})
    add_args = SimpleNamespace(dir="evil", file="implement", path="safe.md", reason="NEW")
    list_args = SimpleNamespace(dir="evil")
    validate_args = SimpleNamespace(dir="evil")
    add_rc = task_context.cmd_add_context(add_args)
    list_rc = task_context.cmd_list_context(list_args)
    validate_rc = task_context.cmd_validate(validate_args)
    output = capsys.readouterr().out

    assert loaded is None
    assert iterated == []
    assert injected is None
    assert "PRIVATE-ID" not in status and "PRIVATE-TITLE" not in status
    assert add_rc != 0 and list_rc != 0 and validate_rc != 0
    assert "PRIVATE-CONTEXT" not in output
    assert (outside / "implement.jsonl").read_text(encoding="utf-8").count("NEW") == 0


def test_task_cli_rejects_task_directory_symlink_before_status_or_hook_io(tmp_path: Path, capsys) -> None:
    """Task CLI lifecycle commands must fail closed on a redirected task dir."""
    task = _load("task_cli_task_dir", ROOT / ".trellis" / "scripts" / "task.py")
    repo = tmp_path / "repo"
    tasks_dir = repo / ".trellis" / "tasks"
    tasks_dir.mkdir(parents=True)
    outside = tmp_path / "outside-task-dir"
    outside.mkdir()
    task_json = outside / "task.json"
    task_json.write_text(
        json.dumps({"id": "PRIVATE-ID", "title": "PRIVATE-TITLE", "status": "planning"}),
        encoding="utf-8",
    )
    evil = tasks_dir / "evil"
    evil.symlink_to(outside, target_is_directory=True)

    task.get_repo_root = lambda: repo
    task.resolve_context_key = lambda: None
    hooks: list[Path] = []
    task.run_task_hooks = lambda _event, path, _repo: hooks.append(path)
    start_rc = task.cmd_start(SimpleNamespace(dir="evil"))
    start_output = capsys.readouterr().out
    unchanged = json.loads(task_json.read_text(encoding="utf-8"))["status"] == "planning"

    task.resolve_active_task = lambda _repo: SimpleNamespace(
        task_path=".trellis/tasks/evil", source="fixture", stale=False,
    )
    current_rc = task.cmd_current(SimpleNamespace(json=True, source=False))
    current_output = capsys.readouterr().out

    task.clear_active_task = lambda _repo: SimpleNamespace(
        task_path=".trellis/tasks/evil", source="fixture", stale=False,
    )
    finish_rc = task.cmd_finish(SimpleNamespace())
    finish_output = capsys.readouterr().out

    assert start_rc != 0 and current_rc == 0 and finish_rc != 0
    assert unchanged and not hooks
    assert "PRIVATE-ID" not in start_output + current_output + finish_output
    assert "PRIVATE-TITLE" not in start_output + current_output + finish_output


def test_task_json_file_symlink_is_rejected_across_cli_store_and_create(tmp_path: Path, capsys) -> None:
    """Every task.json sink must reject a file symlink, not follow its target."""
    task = _load("task_cli_task_json_file", ROOT / ".trellis" / "scripts" / "task.py")
    store = _load_common("task_store", SCRIPTS / "common" / "task_store.py")
    repo = tmp_path / "repo"
    tasks_dir = repo / ".trellis" / "tasks"
    tasks_dir.mkdir(parents=True)
    outside = tmp_path / "outside-task.json"
    original = {
        "id": "PRIVATE-ID",
        "title": "PRIVATE-TITLE",
        "status": "planning",
        "branch": "fixture-branch",
        "children": [],
        "parent": None,
        "meta": {},
    }
    outside.write_text(json.dumps(original), encoding="utf-8")
    safe = tasks_dir / "safe"
    parent = tasks_dir / "parent"
    child = tasks_dir / "child"
    for task_dir in (safe, parent, child):
        task_dir.mkdir()
        (task_dir / "task.json").symlink_to(outside)

    def reset() -> None:
        outside.write_text(json.dumps(original), encoding="utf-8")

    task.get_repo_root = lambda: repo
    task.resolve_context_key = lambda: None
    hooks: list[Path] = []
    task.run_task_hooks = lambda _event, path, _repo: hooks.append(path)
    start_rc = task.cmd_start(SimpleNamespace(dir="safe"))
    start_output = capsys.readouterr().out
    reset()

    task.resolve_active_task = lambda _repo: SimpleNamespace(
        task_path=".trellis/tasks/safe", source="fixture", stale=False,
    )
    current_rc = task.cmd_current(SimpleNamespace(json=True, source=False))
    current_output = capsys.readouterr().out
    reset()

    task.clear_active_task = lambda _repo: SimpleNamespace(
        task_path=".trellis/tasks/safe", source="fixture", stale=False,
    )
    finish_rc = task.cmd_finish(SimpleNamespace())
    finish_output = capsys.readouterr().out
    reset()

    store.get_repo_root = lambda: repo
    set_results = [
        store.cmd_set_branch(SimpleNamespace(dir="safe", branch="changed")),
        store.cmd_set_base_branch(SimpleNamespace(dir="safe", base_branch="changed")),
        store.cmd_set_scope(SimpleNamespace(dir="safe", scope="changed")),
        store.cmd_set_meta(SimpleNamespace(dir="safe", key="fixture", value="changed")),
    ]
    capsys.readouterr()
    reset()

    add_rc = store.cmd_add_subtask(SimpleNamespace(parent_dir="parent", child_dir="child"))
    capsys.readouterr()
    reset()
    remove_rc = store.cmd_remove_subtask(SimpleNamespace(parent_dir="parent", child_dir="child"))
    capsys.readouterr()
    reset()

    store.archive_task_complete = lambda _task_dir, _repo: {}
    store.run_task_hooks = lambda _event, path, _repo: hooks.append(path)
    archive_rc = store.cmd_archive(SimpleNamespace(name="safe", no_commit=True))
    capsys.readouterr()
    reset()

    # Parent linking is validated before create so a symlinked parent task.json
    # cannot be modified as a side effect of creating a new task.
    store.get_developer = lambda _repo=None: "fixture"
    store.resolve_default_branch = lambda _repo: "main"
    store.run_git = lambda _args, cwd=None: (0, "fixture", "")
    store.generate_task_date_prefix = lambda: "01-01"
    store._has_subagent_platform = lambda _repo: False
    create_args = SimpleNamespace(
        title="New fixture task", assignee="fixture", meta=None, package=None,
        priority=None, slug="new-fixture-task", description="", base_branch=None,
        parent="parent", no_start=True,
    )
    create_rc = store.cmd_create(create_args)
    create_output = capsys.readouterr().out

    output = start_output + current_output + finish_output + create_output
    assert start_rc != 0 and current_rc == 0 and finish_rc != 0
    assert all(rc != 0 for rc in set_results)
    assert add_rc != 0 and remove_rc != 0 and archive_rc != 0 and create_rc != 0
    assert not hooks
    assert outside.read_text(encoding="utf-8") == json.dumps(original)
    assert "PRIVATE-ID" not in output and "PRIVATE-TITLE" not in output


def test_create_initialization_rejects_unsafe_prd_and_jsonl_sinks(tmp_path: Path) -> None:
    """Task create must never follow or overwrite unsafe initialization files."""
    store = _load_common("task_store", SCRIPTS / "common" / "task_store.py")
    repo = tmp_path / "repo"
    tasks_dir = repo / ".trellis" / "tasks"
    tasks_dir.mkdir(parents=True)
    store.get_repo_root = lambda: repo
    store.get_developer = lambda _repo=None: "fixture"
    store.resolve_default_branch = lambda _repo: "main"
    store.run_git = lambda _args, cwd=None: (0, "fixture", "")
    store.generate_task_date_prefix = lambda: "01-01"
    store._has_subagent_platform = lambda _repo: True
    store.run_task_hooks = lambda *_args: None

    def create_args(slug: str) -> SimpleNamespace:
        return SimpleNamespace(
            title="Fixture task",
            assignee="fixture",
            meta=None,
            package=None,
            priority=None,
            slug=slug,
            description="",
            base_branch=None,
            parent=None,
            no_start=True,
        )

    def seed_task_dir(slug: str) -> Path:
        task_dir = tasks_dir / f"01-01-{slug}"
        task_dir.mkdir()
        (task_dir / "task.json").write_text("{}\n", encoding="utf-8")
        return task_dir

    outside = tmp_path / "outside"
    outside.mkdir()

    for index, name in enumerate(("prd.md", "implement.jsonl", "check.jsonl")):
        task_dir = seed_task_dir(f"dangling-{index}")
        link = task_dir / name
        link.symlink_to(outside / f"missing-{index}")
        assert store.cmd_create(create_args(f"dangling-{index}")) != 0
        assert not (outside / f"missing-{index}").exists()

    for index, name in enumerate(("prd.md", "implement.jsonl", "check.jsonl")):
        task_dir = seed_task_dir(f"target-{index}")
        target = outside / f"target-{index}"
        target.write_text("PRIVATE-SENTINEL\n", encoding="utf-8")
        (task_dir / name).symlink_to(target)
        assert store.cmd_create(create_args(f"target-{index}")) != 0
        assert target.read_text(encoding="utf-8") == "PRIVATE-SENTINEL\n"

    for index, name in enumerate(("prd.md", "implement.jsonl", "check.jsonl")):
        task_dir = seed_task_dir(f"fifo-{index}")
        os.mkfifo(task_dir / name)
        assert store.cmd_create(create_args(f"fifo-{index}")) != 0

    for index, name in enumerate(("prd.md", "implement.jsonl", "check.jsonl")):
        task_dir = seed_task_dir(f"directory-{index}")
        (task_dir / name).mkdir()
        assert store.cmd_create(create_args(f"directory-{index}")) != 0

    normal = tasks_dir / "01-01-normal"
    normal.mkdir()
    (normal / "task.json").write_text("{}\n", encoding="utf-8")
    assert store.cmd_create(create_args("normal")) == 0
    assert (normal / "prd.md").is_file()
    assert (normal / "implement.jsonl").is_file()
    assert (normal / "check.jsonl").is_file()


def test_context_jsonl_file_symlink_and_nonregular_are_rejected(tmp_path: Path, capsys) -> None:
    """JSONL add/list/validate must not follow symlink or accept FIFO files."""
    task_context = _load_common("task_context", SCRIPTS / "common" / "task_context.py")
    repo = tmp_path / "repo"
    task_dir = repo / ".trellis" / "tasks" / "safe"
    task_dir.mkdir(parents=True)
    (repo / "safe.md").write_text("SAFE", encoding="utf-8")
    outside = tmp_path / "outside-implement.jsonl"
    outside.write_text(json.dumps({"file": "safe.md", "reason": "PRIVATE-CONTEXT"}) + "\n", encoding="utf-8")
    jsonl_link = task_dir / "implement.jsonl"
    jsonl_link.symlink_to(outside)
    task_context.get_repo_root = lambda: repo

    add_rc = task_context.cmd_add_context(
        SimpleNamespace(dir="safe", file="implement", path="safe.md", reason="NEW")
    )
    add_output = capsys.readouterr().out
    list_rc = task_context.cmd_list_context(SimpleNamespace(dir="safe"))
    list_output = capsys.readouterr().out
    validate_rc = task_context.cmd_validate(SimpleNamespace(dir="safe"))
    validate_output = capsys.readouterr().out

    jsonl_link.unlink()
    fifo = task_dir / "check.jsonl"
    os.mkfifo(fifo)
    fifo_add_rc = task_context.cmd_add_context(
        SimpleNamespace(dir="safe", file="check", path="safe.md", reason="FIFO")
    )
    capsys.readouterr()
    fifo_validate_rc = task_context.cmd_validate(SimpleNamespace(dir="safe"))
    fifo_validate_output = capsys.readouterr().out
    fifo_list_rc = task_context.cmd_list_context(SimpleNamespace(dir="safe"))
    fifo_list_output = capsys.readouterr().out

    assert add_rc != 0 and list_rc != 0 and validate_rc != 0
    assert fifo_add_rc != 0 and fifo_validate_rc != 0 and fifo_list_rc != 0
    output = add_output + list_output + validate_output + fifo_validate_output + fifo_list_output
    assert "PRIVATE-CONTEXT" not in output
    assert outside.read_text(encoding="utf-8").count("NEW") == 0


def test_task_json_hooks_and_linear_sync_reject_file_symlink(tmp_path: Path, capsys) -> None:
    """Shared hook and Linear readers/writers must enforce the same file gate."""
    task_utils = _load_common("task_utils", SCRIPTS / "common" / "task_utils.py")
    config = _load_common("config", SCRIPTS / "common" / "config.py")
    linear = _load("linear_sync_file_gate", ROOT / ".trellis" / "scripts" / "hooks" / "linear_sync.py")
    repo = tmp_path / "repo"
    task_dir = repo / ".trellis" / "tasks" / "safe"
    task_dir.mkdir(parents=True)
    outside = tmp_path / "outside-task.json"
    outside.write_text(json.dumps({"id": "PRIVATE-ID", "title": "PRIVATE-TITLE"}), encoding="utf-8")
    task_json = task_dir / "task.json"
    task_json.symlink_to(outside)
    config.get_hooks = lambda _event, _repo: ["true"]

    import subprocess

    calls: list[Path] = []
    original_run = subprocess.run
    subprocess.run = lambda *args, **kwargs: calls.append(Path(kwargs["env"]["TASK_JSON_PATH"]))  # type: ignore[assignment]
    try:
        task_utils.run_task_hooks("after_start", task_json, repo)
    finally:
        subprocess.run = original_run

    old_env = os.environ.get("TASK_JSON_PATH")
    os.environ["TASK_JSON_PATH"] = str(task_json)
    try:
        try:
            linear._read_task()
            linear_read_rc = 0
        except SystemExit as exc:
            linear_read_rc = int(exc.code or 1)
        try:
            linear._write_task({"title": "CHANGED"}, str(task_json))
            linear_write_rc = 0
        except SystemExit as exc:
            linear_write_rc = int(exc.code or 1)
    finally:
        if old_env is None:
            os.environ.pop("TASK_JSON_PATH", None)
        else:
            os.environ["TASK_JSON_PATH"] = old_env
    captured = capsys.readouterr()
    output = captured.out + captured.err

    assert calls == []
    assert linear_read_rc != 0 and linear_write_rc != 0
    assert outside.read_text(encoding="utf-8") == json.dumps({"id": "PRIVATE-ID", "title": "PRIVATE-TITLE"})
    assert "PRIVATE-ID" not in output and "PRIVATE-TITLE" not in output


def test_update_marker_is_opaque_private_and_symlink_safe(tmp_path: Path) -> None:
    """Marker identity and all runtime I/O stay private and contained."""
    session_context = _load_common("session_context", SCRIPTS / "common" / "session_context.py")
    repo = tmp_path / "repo"
    (repo / ".trellis").mkdir(parents=True)
    raw_identity = "raw/TERM_SESSION_ID-private"

    marker = session_context._update_marker_path(repo, raw_identity)
    assert marker is not None
    assert raw_identity not in str(marker)
    assert session_context._mark_update_check_attempted(repo, raw_identity)
    assert not session_context._mark_update_check_attempted(repo, raw_identity)
    runtime = repo / ".trellis" / ".runtime"
    assert stat.S_IMODE(runtime.stat().st_mode) == 0o700
    assert stat.S_IMODE(marker.stat().st_mode) == 0o600
    assert session_context._marker_exists(repo, marker)

    outside = tmp_path / "outside-marker"
    outside.write_text("UNCHANGED", encoding="utf-8")
    marker.unlink()
    marker.symlink_to(outside)
    assert not session_context._marker_exists(repo, marker)
    assert session_context._mark_update_check_attempted(repo, raw_identity)
    assert outside.read_text(encoding="utf-8") == "UNCHANGED"
    assert not marker.is_symlink()
    assert stat.S_IMODE(marker.stat().st_mode) == 0o600

    marker.unlink()
    runtime.rmdir()
    runtime_target = tmp_path / "runtime-outside"
    runtime_target.mkdir()
    runtime.symlink_to(runtime_target, target_is_directory=True)
    assert session_context._update_marker_path(repo, "other-identity") is None
    assert session_context._mark_update_check_attempted(repo, "other-identity")
    assert list(runtime_target.iterdir()) == []


def test_ticket_cwd_symlink_loop_fails_closed(tmp_path: Path) -> None:
    active = _load_common("active_task", SCRIPTS / "common" / "active_task.py")
    repo = tmp_path / "repo"
    repo.mkdir()
    loop = repo / "cwd-loop"
    loop.symlink_to(loop)
    assert active._ticket_cwd_matches_repo({"cwd": str(loop)}, repo) is False


def test_runtime_metadata_is_minimal_and_private(tmp_path: Path) -> None:
    active = _load_common("active_task", SCRIPTS / "common" / "active_task.py")
    raw = {
        "session_id": "fixture-session-id",
        "conversation_id": "fixture-conversation-id",
        "transcript_path": "/private/fixture/transcript.jsonl",
        "platform": "codex",
        "current_task": ".trellis/tasks/fixture",
        "current_run": None,
    }
    metadata = active._context_metadata(raw, "codex", "codex_session_deadbeef")
    assert not any(key in metadata for key in ("session_id", "conversation_id", "transcript_path"))

    path = tmp_path / ".trellis" / ".runtime" / "sessions" / "fixture.json"
    assert active._write_json(path, metadata)
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert stat.S_IMODE(path.parent.stat().st_mode) == 0o700
    assert stat.S_IMODE(path.parent.parent.stat().st_mode) == 0o700
    persisted = json.loads(path.read_text(encoding="utf-8"))
    assert "fixture-session-id" not in json.dumps(persisted)
    assert "fixture-conversation-id" not in json.dumps(persisted)
    assert "/private/fixture" not in json.dumps(persisted)
    key = active._context_key("codex", "session", "fixture-session-id")
    assert "fixture-session-id" not in key
    assert key.startswith("codex_session_")


def test_source_no_fixed_tmp_diagnostics_or_logs() -> None:
    logger = (ROOT / "Sources" / "PetDock" / "PetLogger.swift").read_text(encoding="utf-8")
    main = (ROOT / "Sources" / "PetDock" / "main.swift").read_text(encoding="utf-8")
    diagnose = (ROOT / "tools" / "diagnose.swift").read_text(encoding="utf-8")
    assert "/tmp/petdock.log" not in logger
    assert "/tmp/petdock-diagnose.txt" not in main
    assert "/tmp/petdock-diagnose.txt" not in diagnose


def test_child_environment_source_is_allowlist() -> None:
    rate = (ROOT / "Sources" / "PetDock" / "Data" / "RateLimitClient.swift").read_text(encoding="utf-8")
    assert "var env = baseEnvironment" not in rate
    assert "OPENAI_API_KEY" not in rate


def test_token_cache_key_is_versioned_and_path_free() -> None:
    token = (ROOT / "Sources" / "PetDock" / "Data" / "TokenUsageLogReader.swift").read_text(encoding="utf-8")
    assert "v2:" in token
    assert "memCache[file.path]" not in token
    assert "memCache[key]" in token
