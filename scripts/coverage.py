#!/usr/bin/env python3
"""Export and merge native Xcode coverage; never average coverage percentages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True)


def app_report(report):
    targets = [t for t in report["targets"] if t["name"] == "UnArchiver.app"]
    if len(targets) != 1 or not targets[0]["executableLines"]:
        raise ValueError("Expected one instrumented UnArchiver.app target")
    app = targets[0]
    for item in [app, *app["files"]]:
        if not 0 <= item["coveredLines"] <= item["executableLines"]:
            raise ValueError("Invalid coverage counts")
    return app


def source_manifest(app, root):
    files = {}
    for file in app["files"]:
        path = Path(file["path"])
        relative = path.resolve().relative_to(root.resolve()).as_posix()
        if not relative.startswith("UnArchiver/") or relative in files:
            raise ValueError(f"Unexpected or duplicate app source: {relative}")
        files[relative] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                           "executableLines": file["executableLines"]}
    if not files:
        raise ValueError("No app source files")
    return files


def export(result, output, suite, root):
    output.mkdir(parents=True, exist_ok=True)
    raw = json.loads(command("xcrun", "xccov", "view", "--report", "--json", str(result)))
    app = app_report(raw)
    # Export the native report AND archive: the archive is required to merge
    # execution data correctly, including overlapping Swift coverage regions.
    bundle = json.loads(command("xcrun", "xcresulttool", "get", "object", "--legacy",
                                "--format", "json", "--path", str(result)))
    actions = [a["actionResult"]["coverage"] for a in bundle["actions"]["_values"]
               if "reportRef" in a.get("actionResult", {}).get("coverage", {})]
    if len(actions) != 1 or "archiveRef" not in actions[0]:
        raise ValueError("Expected one test action with a coverage report and archive")
    for key, kind, suffix in [("reportRef", "file", "xccovreport"),
                               ("archiveRef", "directory", "xccovarchive")]:
        command("xcrun", "xcresulttool", "export", "object", "--legacy", "--type", kind,
                "--path", str(result), "--id", actions[0][key]["id"]["_value"],
                "--output-path", str(output / f"{suite}.{suffix}"))
    metadata = {"version": 1, "commit": command("git", "rev-parse", "HEAD").strip(),
                "suite": suite, "files": source_manifest(app, root)}
    (output / f"{suite}.manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / f"{suite}.json").write_text(json.dumps(raw, indent=2) + "\n")


def validate_manifests(manifests):
    if len(manifests) != 3 or {m.get("suite") for m in manifests} != {"unit", "ui", "ui-scrolling"}:
        raise ValueError("Require exactly one unit, ui and ui-scrolling input")
    first = manifests[0]
    for item in manifests:
        if (item.get("version") != 1 or not item.get("commit") or not item.get("files")
                or item["commit"] != first["commit"] or item["files"] != first["files"]):
            raise ValueError("Coverage inputs must have matching commits, sources and executable counts")


def file_map(app):
    # Native xccov merges using original absolute paths. All jobs check out to
    # the same repository path. Refuse mismatches instead of silently dropping files.
    files = {f["path"]: f for f in app["files"]}
    if len(files) != len(app["files"]):
        raise ValueError("Duplicate paths in coverage report")
    return files


def validate_merged(merged, *inputs):
    merged_files = file_map(merged)
    for original in inputs:
        original_files = file_map(original)
        if merged_files.keys() != original_files.keys():
            raise ValueError("Merged coverage changed the source file set")
        for path, file in original_files.items():
            result = merged_files[path]
            if (result["executableLines"] != file["executableLines"]
                    or result["coveredLines"] < file["coveredLines"]):
                raise ValueError(f"Invalid merged coverage for {path}")
        if (merged["executableLines"] != original["executableLines"]
                or merged["coveredLines"] < original["coveredLines"]):
            raise ValueError("Invalid merged app coverage")


def native_merge(output, name, *prefixes):
    arguments = []
    for prefix in prefixes:
        arguments.extend([str(prefix.with_suffix(".xccovreport")), str(prefix.with_suffix(".xccovarchive"))])
    report = output / f"{name}.xccovreport"
    command("xcrun", "xccov", "merge", "--outReport", str(report),
            "--outArchive", str(output / f"{name}.xccovarchive"), *arguments)
    return json.loads(command("xcrun", "xccov", "view", "--json", str(report)))


def percentage(item):
    hit, total = item["coveredLines"], item["executableLines"]
    return f"{100 * hit / total:.1f}% ({hit}/{total})" if total else "— (0/0)"


def render(reports, commit):
    columns = [app_report(r) for r in reports]
    lines = ["<!-- coverage-report -->", "## App line coverage", "",
             "| Scope | Coverage (covered/executable lines) |", "|---|---:|"]
    for name, app in zip(["Unit tests", "UI tests (including scrolling)", "Combined"], columns):
        lines.append(f"| {name} | {percentage(app)} |")
    lines += ["", "Combined coverage uses xccov's native execution-data merge; percentages are not averaged or added.",
              "Scope: UnArchiver app target; test bundles, dependencies and the share extension are excluded.",
              f"Commit: `{commit}`", "", "| File | Unit | UI | Combined |", "|---|---:|---:|---:|"]
    maps = [file_map(app) for app in columns]
    for path in sorted(maps[2]):
        # Keep directories to disambiguate files with the same basename.
        label = "UnArchiver/" + path.rsplit("/UnArchiver/", 1)[1]
        lines.append(f"| {label} | {' | '.join(percentage(files[path]) for files in maps)} |")
    return "\n".join(lines) + "\n"


def summarize(inputs, output):
    manifests = [json.loads((inputs / f"{suite}.manifest.json").read_text())
                 for suite in ["unit", "ui", "ui-scrolling"]]
    validate_manifests(manifests)
    raw = {m["suite"]: json.loads((inputs / f"{m['suite']}.json").read_text()) for m in manifests}
    # Check source paths/counts before invoking native merge as well as after it.
    for suite in ["ui", "ui-scrolling"]:
        a, b = file_map(app_report(raw["unit"])), file_map(app_report(raw[suite]))
        if a.keys() != b.keys() or any(a[p]["executableLines"] != b[p]["executableLines"] for p in a):
            raise ValueError("Input coverage paths or executable counts differ")
    output.mkdir(parents=True, exist_ok=True)
    ui = native_merge(output, "ui", inputs / "ui", inputs / "ui-scrolling")
    validate_merged(app_report(ui), app_report(raw["ui"]), app_report(raw["ui-scrolling"]))
    combined = native_merge(output, "combined", inputs / "unit", output / "ui")
    validate_merged(app_report(combined), app_report(raw["unit"]), app_report(ui))
    reports = [raw["unit"], ui, combined]
    summary = render(reports, manifests[0]["commit"])
    (output / "coverage_comment.md").write_text(summary)
    for name, report in zip(["unit", "ui", "combined"], reports):
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
    reporter.add_argument("inputs", type=Path)
    reporter.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "export":
        export(args.result, args.output, args.suite, args.root)
    else:
        summarize(args.inputs, args.output)
