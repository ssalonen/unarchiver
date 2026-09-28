#!/usr/bin/env python3
"""Fail closed on XCTest assertions, crashes, missing tests and runner failures."""
import re
import sys
from pathlib import Path


def succeeded(log: str, exit_code: int) -> bool:
    # XCTest can finish with TEST EXECUTE FAILED after assertion failures or a
    # process crash. Never treat that footer as a benign profiling failure.
    if exit_code != 0 or "** TEST EXECUTE SUCCEEDED **" not in log:
        return False
    if re.search(r"Test (?:Case|Suite) .* failed|Restarting after unexpected exit|error: -\[", log):
        return False
    counts = re.findall(r"Executed (\d+) tests?, with (\d+) failures?", log)
    return bool(counts) and any(int(count) > 0 for count, _ in counts) and all(int(failures) == 0 for _, failures in counts)


if __name__ == "__main__":
    if not succeeded(Path(sys.argv[1]).read_text(), int(sys.argv[2])):
        print("::error::Unit tests did not complete successfully. See unit-test-diagnostics.")
        sys.exit(1)
