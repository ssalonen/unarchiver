import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from coverage import app_report, export, native_merge, percentage, render, validate_manifests, validate_merged


def report(hit=1, total=4):
    return {"targets": [{"name": "UnArchiverTests.xctest", "coveredLines": 99, "executableLines": 99},
                        {"name": "UnArchiver.app", "coveredLines": hit, "executableLines": total,
                         "files": [{"path": "/repo/UnArchiver/A.swift", "coveredLines": hit, "executableLines": total}]}]}


def manifests():
    return [{"version": 1, "commit": "abc", "suite": suite,
             "files": {"UnArchiver/A.swift": {"sha256": "hash", "executableLines": 4}}}
            for suite in ["unit", "ui", "ui-scrolling"]]


class CoverageTests(unittest.TestCase):
    def test_selects_exact_app_target_and_rejects_missing_instrumentation(self):
        self.assertEqual(app_report(report())["coveredLines"], 1)
        for value in [{"targets": []}, report(total=0), report(hit=5), {"targets": report()["targets"] * 2}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                app_report(value)

    def test_requires_all_suites_and_identical_source_versions(self):
        validate_manifests(manifests())
        mutations = [lambda m: m.pop(), lambda m: m[0].update(suite="ui"),
                     lambda m: m[0].update(commit="other"),
                     lambda m: m[0]["files"].clear(),
                     lambda m: m[0]["files"]["UnArchiver/A.swift"].update(sha256="changed"),
                     lambda m: m[0]["files"]["UnArchiver/A.swift"].update(executableLines=5)]
        for mutate in mutations:
            data = manifests()
            mutate(data)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                validate_manifests(data)

    def test_merge_validates_denominator_paths_and_monotonic_coverage(self):
        validate_merged(app_report(report(3)), app_report(report(2)), app_report(report(1)))
        for invalid in [report(1), report(3, 5)]:
            with self.assertRaises(ValueError):
                validate_merged(app_report(invalid), app_report(report(2)))
        invalid = report(3)
        invalid["targets"][1]["files"][0]["path"] = "/other/A.swift"
        with self.assertRaises(ValueError):
            validate_merged(app_report(invalid), app_report(report(2)))

    def test_native_merge_always_supplies_execution_archives(self):
        with tempfile.TemporaryDirectory() as tmp, patch("coverage.command", side_effect=["", json.dumps(report(3))]) as run:
            result = native_merge(Path(tmp), "combined", Path("in/unit"), Path("in/ui"))
        self.assertEqual(result, report(3))
        args = run.call_args_list[0].args
        self.assertEqual(args[-4:], ("in/unit.xccovreport", "in/unit.xccovarchive", "in/ui.xccovreport", "in/ui.xccovarchive"))

    def test_render_uses_native_merged_counts_not_sum_or_average(self):
        text = render([report(2), report(2), report(3)], "abc")
        self.assertIn("| Combined | 75.0% (3/4) |", text)
        self.assertNotIn("99/99", text)
        self.assertIn("UnArchiver/A.swift", text)
        self.assertEqual(percentage({"coveredLines": 1, "executableLines": 10}), "10.0% (1/10)")

    def test_export_preserves_native_summary_and_archives(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "UnArchiver/A.swift"
            source.parent.mkdir()
            source.write_text("some source\n")
            raw = report()
            raw["targets"][1]["files"][0]["path"] = str(source)
            bundle = {"actions": {"_values": [{"actionResult": {"coverage": {
                "reportRef": {"id": {"_value": "report-id"}},
                "archiveRef": {"id": {"_value": "archive-id"}}}}}]}}
            with patch("coverage.command", side_effect=[json.dumps(raw), json.dumps(bundle), "", "", "abc\n"]) as run:
                export(root / "test.xcresult", root / "out", "unit", root)
            self.assertEqual(json.loads((root / "out/unit.json").read_text()), raw)
            metadata = json.loads((root / "out/unit.manifest.json").read_text())
            self.assertEqual(metadata["suite"], "unit")
            self.assertEqual(metadata["files"]["UnArchiver/A.swift"]["executableLines"], 4)
            self.assertIn("directory", run.call_args_list[3].args)
            with patch("coverage.command", side_effect=[json.dumps(raw), json.dumps({"actions": {"_values": []}})]):
                with self.assertRaises(ValueError):
                    export(root / "test.xcresult", root / "out", "unit", root)


if __name__ == "__main__":
    unittest.main()
