#!/usr/bin/env python3
"""Unit tests for the offline documentation checker."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from check_docs import check_repository


class CheckDocsTests(unittest.TestCase):
    def check(self, files: dict[str, str]):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative, contents in files.items():
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(contents, encoding="utf-8")
            findings = check_repository(root)
            return findings

    def test_clean_repository(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n\n- [Guide](guide.md)\n",
                "docs/guide.md": "# Guide\n",
                ".trellis/spec/macos/index.md": "[Guide](documentation-guidelines.md)\n",
                ".trellis/spec/macos/documentation-guidelines.md": "# Documentation\n",
            }
        )
        self.assertEqual(findings, [])

    def test_broken_local_link(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n[Missing](docs/missing.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n",
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        self.assertTrue(any(f.code == "broken-link" for f in findings))

    def test_uncatalogued_document(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n",
                "docs/guide.md": "# Guide\n",
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        self.assertTrue(any(f.code == "uncatalogued-doc" for f in findings))

    def test_legacy_top_level_document_path(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n[Old](docs/data-layer.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n",
                "docs/data-layer.md": "# Old\n",
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        self.assertTrue(any(f.code == "legacy-doc-path" for f in findings))

    def test_private_user_path_and_window_id(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n- [Guide](guide.md)\n",
                "docs/guide.md": "Runtime path /Users/alice/project and wid=12345.\n",
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        codes = {finding.code for finding in findings}
        self.assertIn("private-path", codes)
        self.assertIn("private-window-id", codes)

    def test_private_coordinates_hashes_and_trailer(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n- [Guide](guide.md)\n",
                "docs/guide.md": (
                    "CGRect(x: 12, y: 34)\n"
                    "frame=(56, 78)\n"
                    "CDHash=0123456789abcdef\n"
                    "0123456789abcdef0123456789abcdef01234567\n"
                    "Co-Authored" + "-By: Example <example@example.com>\n"
                ),
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        codes = {finding.code for finding in findings}
        self.assertIn("private-coordinate", codes)
        self.assertIn("private-cdhash", codes)
        self.assertIn("private-hash", codes)
        self.assertIn("private-coauthored", codes)

    def test_angle_bracket_placeholders_are_allowed(self):
        findings = self.check(
            {
                "README.md": "[Docs](docs/README.md)\n",
                "README.zh-CN.md": "[文档](docs/README.md)\n",
                "docs/README.md": "# Docs\n- [Guide](guide.md)\n",
                "docs/guide.md": "/Users/<user>/project wid=<wid> x=<qx>, y=<qy>\n",
                ".trellis/spec/macos/index.md": "# Index\n",
            }
        )
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()
