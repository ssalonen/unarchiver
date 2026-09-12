#!/usr/bin/env python3
"""Tests for GitHub Actions annotations emitted after a failed Fastlane lane."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANNOTATOR = ROOT / "scripts" / "fastlane_failure_annotation.py"


class FastlaneFailureAnnotationTests(unittest.TestCase):
    def annotate(self, log: str) -> str:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as file:
            file.write(log)
            path = file.name
        self.addCleanup(Path(path).unlink)
        result = subprocess.run(
            ["python3", str(ANNOTATOR), path],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout

    def test_https_match_clone_failure_points_to_matchfile_and_explains_ssh_fix(self) -> None:
        output = self.annotate(
            "fatal: could not read Username for 'https://github.com': terminal prompts disabled\n"
            "[!] Error cloning certificates git repo, please make sure you have access to the repository\n"
        )

        self.assertIn("::error file=fastlane/Matchfile,line=8,title=Fastlane match authentication::", output)
        self.assertIn("MATCH_GIT_URL uses HTTPS", output)
        self.assertIn("git@github.com", output)

    def test_fastlane_error_points_to_the_reported_fastfile_line(self) -> None:
        output = self.annotate(
            "[06:17:44]: Called from Fastfile at line 68\n"
            "[!] A distribution profile is missing\n"
        )

        self.assertIn("::error file=fastlane/Fastfile,line=68,title=Fastlane beta failed::", output)
        self.assertIn("A distribution profile is missing", output)

    def test_percent_and_newline_are_escaped_for_workflow_commands(self) -> None:
        output = self.annotate("[!] failure is 100% reproducible\nnext line\n")

        self.assertIn("100%25 reproducible%0Anext line", output)


if __name__ == "__main__":
    unittest.main()
