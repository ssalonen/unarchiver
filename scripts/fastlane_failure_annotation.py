#!/usr/bin/env python3
"""Turn the useful part of a failed Fastlane log into a GitHub annotation."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def escape_workflow_command(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def fastlane_error(log: str) -> str:
    match = re.search(r"^\[!\]\s+(.+?)(?:\n([^\[][^\n]*))?(?:\n|$)", log, re.MULTILINE)
    if not match:
        return "Fastlane failed. Read the step log for the underlying error."
    return "\n".join(part.strip() for part in match.groups() if part and part.strip())


def annotation(log: str) -> str:
    if "could not read Username for 'https://github.com'" in log and "Error cloning certificates git repo" in log:
        title = "Fastlane match authentication"
        location = "file=fastlane/Matchfile,line=8"
        message = (
            "MATCH_GIT_URL uses HTTPS, but this job loads MATCH_REPO_KEY into ssh-agent. "
            "Set MATCH_GIT_URL to the repository SSH URL (for example, git@github.com:OWNER/REPO.git) "
            "or provide HTTPS credentials; the deploy key alone cannot authenticate an HTTPS clone."
        )
    else:
        title = "Fastlane beta failed"
        line = re.search(r"Called from Fastfile at line (\d+)", log)
        location = f"file=fastlane/Fastfile,line={line.group(1)}" if line else "file=fastlane/Fastfile"
        message = fastlane_error(log)
    return f"::error {location},title={title}::{escape_workflow_command(message)}"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} FASTLANE_LOG", file=sys.stderr)
        return 2
    print(annotation(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
