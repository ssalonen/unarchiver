#!/usr/bin/env python3
"""Export xccov executable/covered line sets and union them without double counting."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True)


def parse_lines(text):
    executable, covered = set(), set()
    for line in text.splitlines():
        match = re.fullmatch(r"\s*(\d+):\s*(\d+|\*)(?:\s*\[)?\s*", line)
        if not match:
            # xccov also emits subranges such as (column, length, count).
            if line.strip() and not re.fullmatch(r"\s*(?:\]|\(.*\),?)\s*", line):
                raise ValueError(f"Unexpected xccov line: {line!r}")
            continue
        number, count = match.groups()
        if count != "*":
            executable.add(int(number))
            if int(count) > 0:
                covered.add(int(number))
    return executable, covered


def export(result, output, suite, root):
    report = json.loads(command("xcrun", "xccov", "view", "--report", "--json", str(result)))
    targets = [t for t in report["targets"] if t["name"] == "UnArchiver.app"]
    if len(targets) != 1 or not targets[0]["executableLines"]:
        raise ValueError("Expected one instrumented UnArchiver.app target")
    files = {}
    for file in targets[0]["files"]:
        path = Path(file["path"])
        relative = path.resolve().relative_to(root.resolve()).as_posix()
        if not relative.startswith("UnArchiver/"):
            raise ValueError(f"Unexpected app source: {relative}")
        if relative in files:
            raise ValueError(f"Duplicate source: {relative}")
        executable, covered = parse_lines(command(
            "xcrun", "xccov", "view", "--archive", "--file", str(path), str(result)))
        if len(executable) != file["executableLines"] or len(covered) != file["coveredLines"]:
            raise ValueError(f"Line data disagrees with xccov summary for {relative}")
        files[relative] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                           "executable": sorted(executable), "covered": sorted(covered)}
    data = {"version": 1, "commit": command("git", "rev-parse", "HEAD").strip(),
            "suite": suite, "files": files}
    validate(data)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2) + "\n")
    output.with_suffix(".xccov.json").write_text(json.dumps(report, indent=2) + "\n")


def validate(data):
    if data.get("version") != 1 or not data.get("commit") or not data.get("files"):
        raise ValueError("Missing or invalid coverage data")
    total = 0
    for path, file in data["files"].items():
        executable, covered = set(file["executable"]), set(file["covered"])
        if not file.get("sha256") or not covered <= executable:
            raise ValueError(f"Invalid coverage for {path}")
        if any(type(line) is not int or line <= 0 for line in executable):
            raise ValueError(f"Invalid line number in {path}")
        total += len(executable)
    if total == 0:
        raise ValueError("No executable app lines")


def merge(*reports):
    if not reports:
        raise ValueError("No coverage inputs")
    for report in reports:
        validate(report)
    first = reports[0]
    result = {"version": 1, "commit": first["commit"], "files": {}}
    for report in reports:
        if report["commit"] != first["commit"] or report["files"].keys() != first["files"].keys():
            raise ValueError("Coverage inputs must describe the same commit and source files")
        for path, file in report["files"].items():
            original = first["files"][path]
            if file["sha256"] != original["sha256"] or set(file["executable"]) != set(original["executable"]):
                raise ValueError(f"Source or executable-line mismatch: {path}")
            merged = result["files"].setdefault(path, {**file, "covered": []})
            merged["covered"] = sorted(set(merged["covered"]) | set(file["covered"]))
    return result


def counts(files):
    return (sum(len(set(f["covered"])) for f in files),
            sum(len(set(f["executable"])) for f in files))


def percentage(files):
    hit, total = counts(files)
    return f"{100 * hit / total:.1f}% ({hit}/{total})" if total else "— (0/0)"


def summarize(inputs, output):
    reports = [json.loads(path.read_text()) for path in inputs]
    by_suite = {r["suite"]: r for r in reports}
    if len(by_suite) != len(reports) or set(by_suite) != {"unit", "ui", "ui-scrolling"}:
        raise ValueError("Require exactly one unit, ui and ui-scrolling coverage input")
    unit = by_suite["unit"]
    ui = merge(by_suite["ui"], by_suite["ui-scrolling"])
    combined = merge(unit, ui)
    columns = [unit, ui, combined]
    lines = ["<!-- coverage-report -->", "## App line coverage", "",
             "| Scope | Coverage (covered/executable lines) |", "|---|---:|"]
    for name, report in zip(["Unit tests", "UI tests (including scrolling)", "Combined"], columns):
        lines.append(f"| {name} | {percentage(report['files'].values())} |")
    lines += ["", "Combined coverage is the union of covered source lines, not an average of percentages.",
              "Scope: UnArchiver app target; test bundles, dependencies and the share extension are excluded.",
              f"Commit: `{combined['commit']}`", "",
              "| File | Unit | UI | Combined |", "|---|---:|---:|---:|"]
    for path in sorted(combined["files"]):
        values = [percentage([r["files"][path]]) for r in columns]
        lines.append(f"| {path} | {' | '.join(values)} |")
    output.mkdir(parents=True, exist_ok=True)
    summary = "\n".join(lines) + "\n"
    (output / "coverage_comment.md").write_text(summary)
    for name, report in zip(["unit", "ui", "combined"], columns):
        (output / f"{name}.json").write_text(json.dumps(report, indent=2) + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(summary)
    print(summary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    collector = commands.add_parser("export")
    collector.add_argument("result", type=Path)
    collector.add_argument("output", type=Path)
    collector.add_argument("--suite", required=True, choices=["unit", "ui", "ui-scrolling"])
    collector.add_argument("--root", type=Path, default=Path.cwd())
    reporter = commands.add_parser("report")
    reporter.add_argument("inputs", type=Path, nargs="+")
    reporter.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "export":
        export(args.result, args.output, args.suite, args.root)
    else:
        summarize(args.inputs, args.output)
