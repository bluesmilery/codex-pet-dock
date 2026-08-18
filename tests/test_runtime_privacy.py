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
