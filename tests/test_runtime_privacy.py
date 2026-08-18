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
