#!/usr/bin/env python3
"""Offline checks for the project's public Markdown documentation.

The checker deliberately reads only the public Markdown paths that are part of
the repository's documentation contract.  It has no network or credential
access and can be imported by the small unit-test harness in ``tests/``.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Optional
from urllib.parse import unquote


@dataclass(frozen=True)
class Finding:
    """A deterministic, line-oriented checker finding."""

    path: str
    line: int
    code: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.code}: {self.message}"


# These files were moved into architecture/development/verification by the
# documentation reorganisation.  Their old top-level paths must not return.
LEGACY_DOC_PATHS = frozenset(
    {
        "docs/data-layer.md",
        "docs/dock-obstacle-avoidance.md",
        "docs/final-success-criteria.md",
        "docs/pet-window-detection.md",
        "docs/success-criteria.md",
        "docs/trellis-setup.md",
    }
)

_MARKDOWN_LINK_RE = re.compile(
    r"!?(?:\[[^\]]*\])\(\s*(?:<([^>\n]+)>|([^\s)]+))"
    r"(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)",
)
_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
_USER_PATH_RE = re.compile(r"/Users/(?P<user>[^/\s<>]+)(?:/|$)")
_WINDOW_ID_RE = re.compile(
    r"(?<![A-Za-z0-9_])[`\"']?(?:wid|window[_ -]?id|kCGWindowNumber)"
    r"[`\"']?\s*(?:=|:)\s*"
    r"(?P<value>\d+)\b",
    re.IGNORECASE,
)
_COORDINATE_RE = re.compile(
    r"(?:"
    r"\b(?:x|y|left|top|originX|originY)\s*[=:]\s*-?\d+(?:\.\d+)?\b"
    r"|\b(?:CGRect|CGPoint|NSRect)\s*\(\s*-?\d+(?:\.\d+)?\s*,"
    r"\s*-?\d+(?:\.\d+)?"
    r"|\b(?:frame|bounds|origin|position|rect)\s*[=:]\s*[\(\[]\s*"
    r"-?\d+(?:\.\d+)?\s*[, ]\s*-?\d+(?:\.\d+)?"
    r'|["\'](?:X|Y|Width|Height)["\']\s*:\s*-?\d+(?:\.\d+)?\b'
    r")",
    re.IGNORECASE,
)
_CDHASH_RE = re.compile(
    r"\bCDHash\s*[:=]\s*(?!<)[0-9a-fA-F]{4,}\b", re.IGNORECASE
)
_LONG_HASH_RE = re.compile(
    r"(?<![0-9a-fA-F])(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})(?![0-9a-fA-F])"
)
_COAUTHORED_TRAILER_RE = re.compile(
    r"^\s*(?:[-*]\s*)?Co-Authored-By\s*:", re.IGNORECASE
)


def _relative(root: Path, path: Path) -> str:
    """Return a stable POSIX path for output and finding sorting."""

    return path.relative_to(root).as_posix()


def _public_markdown_paths(root: Path) -> list[Path]:
    """Return the documented Markdown input set in deterministic order."""

    candidates: set[Path] = set()
    for relative in ("README.md", "README.zh-CN.md"):
        path = root / relative
        if path.is_file() and not path.is_symlink():
            candidates.add(path)

    for pattern in ("docs/**/*.md", ".trellis/spec/macos/**/*.md"):
        for path in root.glob(pattern):
            if path.is_file() and not path.is_symlink():
                candidates.add(path)

    return sorted(candidates, key=lambda path: _relative(root, path))


def _line_number(contents: str, offset: int) -> int:
    return contents.count("\n", 0, offset) + 1


def _iter_links(contents: str) -> Iterator[tuple[int, str, bool]]:
    for match in _MARKDOWN_LINK_RE.finditer(contents):
        target = match.group(1) or match.group(2)
        if target is not None:
            yield _line_number(contents, match.start()), target, match.group(0).startswith("!")


def _mask_link_targets(contents: str) -> str:
    """Replace Markdown link destinations while preserving labels and prose."""

    masked = list(contents)
    for match in _MARKDOWN_LINK_RE.finditer(contents):
        group = 1 if match.group(1) is not None else 2
        start, end = match.span(group)
        for index in range(start, end):
            masked[index] = " "
    return "".join(masked)


def _local_target(root: Path, source: Path, raw_target: str) -> Optional[Path]:
    """Resolve a Markdown target, returning None for intentionally ignored URLs."""

    target = raw_target.strip()
    if not target or target.startswith("#"):
        return None
    if target.lower().startswith(("http:", "https:", "mailto:")):
        return None
    if _SCHEME_RE.match(target):
        return None

    target = target.split("#", 1)[0].split("?", 1)[0]
    if not target:
        return None
    target = unquote(target)
    if _SCHEME_RE.match(target):
        return None

    resolved = (source.parent / target).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return resolved
    return resolved


def _finding(path: Path, root: Path, line: int, code: str, message: str) -> Finding:
    return Finding(_relative(root, path), line, code, message)


def _check_links(root: Path, paths: Iterable[Path]) -> list[Finding]:
    findings: list[Finding] = []
    root_resolved = root.resolve()
    for path in paths:
        contents = path.read_text(encoding="utf-8")
        for line, raw_target, _is_image in _iter_links(contents):
            target = _local_target(root_resolved, path, raw_target)
            if target is None:
                continue
            if target != target.resolve() or not target.is_relative_to(root_resolved):
                findings.append(
                    _finding(
                        path,
                        root,
                        line,
                        "link-outside-root",
                        f"local link escapes repository root: {raw_target}",
                    )
                )
                continue
            if not target.exists():
                findings.append(
                    _finding(
                        path,
                        root,
                        line,
                        "broken-link",
                        f"local link target does not exist: {raw_target}",
                    )
                )
    return findings


def _check_catalog(root: Path, paths: Iterable[Path]) -> list[Finding]:
    findings: list[Finding] = []
    catalog = root / "docs/README.md"
    if not catalog.is_file() or catalog.is_symlink():
        findings.append(
            Finding("docs/README.md", 1, "catalog-missing", "docs/README.md is required")
        )
        return findings

    contents = catalog.read_text(encoding="utf-8")
    linked_docs: set[Path] = set()
    for line, raw_target, is_image in _iter_links(contents):
        if is_image:
            continue
        target = _local_target(root, catalog, raw_target)
        if target is not None and target.is_relative_to(root.resolve()):
            linked_docs.add(target)

    for path in paths:
        relative = _relative(root, path)
        if not relative.startswith("docs/") or relative == "docs/README.md":
            continue
        if path.resolve() not in linked_docs:
            findings.append(
                _finding(
                    path,
                    root,
                    1,
                    "uncatalogued-doc",
                    "documentation file is not linked from docs/README.md",
                )
            )
    return findings


def _check_legacy_paths(root: Path, paths: Iterable[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for path in paths:
        relative = _relative(root, path)
        if relative in LEGACY_DOC_PATHS:
            findings.append(
                _finding(
                    path,
                    root,
                    1,
                    "legacy-doc-path",
                    f"legacy top-level documentation path is forbidden: {relative}",
                )
            )

        contents = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(contents.splitlines(), start=1):
            for legacy in LEGACY_DOC_PATHS:
                if legacy in line and relative != legacy:
                    findings.append(
                        _finding(
                            path,
                            root,
                            line_number,
                            "legacy-doc-path",
                            f"legacy top-level documentation path is referenced: {legacy}",
                        )
                    )
    return findings


def _privacy_findings(path: Path, root: Path, contents: str) -> list[Finding]:
    findings: list[Finding] = []
    for line_number, line in enumerate(contents.splitlines(), start=1):
        scan_line = _mask_link_targets(line)
        if _USER_PATH_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-path",
                    "literal user path under /Users is not allowed",
                )
            )
        if _WINDOW_ID_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-window-id",
                    "numeric window id is not allowed",
                )
            )
        if _COORDINATE_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-coordinate",
                    "runtime coordinate value is not allowed",
                )
            )
        if _CDHASH_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-cdhash",
                    "CDHash value is not allowed",
                )
            )
        if _LONG_HASH_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-hash",
                    "build-specific 40/64-character hash is not allowed",
                )
            )
        if _COAUTHORED_TRAILER_RE.search(scan_line):
            findings.append(
                _finding(
                    path,
                    root,
                    line_number,
                    "private-coauthored",
                    "Co-Authored-By trailer is not allowed",
                )
            )
    return findings


def check_repository(root: Path) -> list[Finding]:
    """Run all offline documentation checks for ``root``.

    Findings are sorted by repository-relative path, line, code, and message so
    CLI output and review evidence remain stable across runs.
    """

    root = Path(root).resolve()
    paths = _public_markdown_paths(root)
    findings = _check_links(root, paths)
    findings.extend(_check_catalog(root, paths))
    findings.extend(_check_legacy_paths(root, paths))

    for path in paths:
        contents = path.read_text(encoding="utf-8")
        findings.extend(_privacy_findings(path, root, contents))

    return sorted(findings, key=lambda finding: (finding.path, finding.line, finding.code, finding.message))


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Check public Markdown documentation offline")
    parser.add_argument("root", nargs="?", default=".", type=Path, help="repository root (default: .)")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    paths = _public_markdown_paths(root)
    findings = check_repository(root)
    for finding in findings:
        print(finding)
    print(f"docs-check: scanned {len(paths)} Markdown files; {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
