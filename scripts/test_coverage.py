import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from coverage import counts, export, merge, parse_lines, percentage, summarize


def report(suite="unit", hit=(1,), lines=(1, 2, 3, 4)):
    return {"version": 1, "commit": "abc", "suite": suite,
            "files": {"UnArchiver/A.swift": {"sha256": "hash", "executable": list(lines), "covered": list(hit)}}}


class CoverageTests(unittest.TestCase):
    def test_archive_parser_ignores_nonexecutable_lines_and_subranges(self):
        self.assertEqual(parse_lines(" 1: *\n 2: 0\n 3: 9 [\n (2, 5, 0)\n ]\n"), ({2, 3}, {3}))
        with self.assertRaises(ValueError):
            parse_lines("unsupported format")

    def test_union_deduplicates_overlap_and_includes_complementary_lines(self):
        unit = report(hit=(1, 2))
        ui = report("ui", hit=(2, 3))
        before = copy.deepcopy(unit)
        combined = merge(unit, ui)
        self.assertEqual(counts(combined["files"].values()), (3, 4))
        self.assertEqual(unit, before)
        self.assertEqual(percentage(combined["files"].values()), "75.0% (3/4)")

    def test_total_is_weighted_by_lines_not_file_percentages(self):
        data = report(hit=(1,), lines=(1,))
        data["files"]["UnArchiver/B.swift"] = {"sha256": "b", "executable": list(range(1, 10)), "covered": []}
        self.assertEqual(percentage(data["files"].values()), "10.0% (1/10)")

    def test_rejects_incompatible_or_incomplete_inputs(self):
        mutations = [lambda r: r.update(commit="other"),
                     lambda r: r["files"].clear(),
                     lambda r: r["files"]["UnArchiver/A.swift"].update(sha256="changed"),
                     lambda r: r["files"]["UnArchiver/A.swift"].update(executable=[1, 2]),
                     lambda r: r["files"]["UnArchiver/A.swift"].update(covered=[99])]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                other = report()
                mutate(other)
                with self.assertRaises(ValueError):
                    merge(report(), other)

    def test_requires_both_ui_shards_and_keeps_same_basename_files_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            inputs = []
            for suite, hit in [("unit", [1]), ("ui", [2]), ("ui-scrolling", [3])]:
                data = report(suite, hit)
                data["files"]["UnArchiver/Other/A.swift"] = {"sha256": "other", "executable": [1], "covered": []}
                path = root / f"{suite}.json"
                path.write_text(json.dumps(data))
                inputs.append(path)
            with patch("builtins.print"), patch.dict("os.environ", {}, clear=True):
                summarize(inputs, root / "out")
                with self.assertRaises(ValueError):
                    summarize(inputs[:2], root / "out")
            ui = json.loads((root / "out/ui.json").read_text())
            combined = json.loads((root / "out/combined.json").read_text())
            self.assertEqual(counts(ui["files"].values()), (2, 5))
            self.assertEqual(counts(combined["files"].values()), (3, 5))
            self.assertIn("UnArchiver/Other/A.swift", (root / "out/coverage_comment.md").read_text())

    def test_export_selects_app_only_and_crosschecks_line_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "UnArchiver/A.swift"
            source.parent.mkdir()
            source.write_text("one\ntwo\n")
            file = {"path": str(source), "executableLines": 2, "coveredLines": 1}
            raw = {"targets": [{"name": "UnArchiverTests.xctest", "executableLines": 9},
                               {"name": "UnArchiver.app", "executableLines": 2, "files": [file]}]}
            with patch("coverage.command", side_effect=[json.dumps(raw), "1: 1\n2: 0\n", "abc\n"]):
                export(root / "test.xcresult", root / "out/unit.json", "unit", root)
            data = json.loads((root / "out/unit.json").read_text())
            self.assertEqual(counts(data["files"].values()), (1, 2))
            with patch("coverage.command", side_effect=[json.dumps(raw), "1: 1\n2: 1\n"]):
                with self.assertRaises(ValueError):
                    export(root / "test.xcresult", root / "bad.json", "unit", root)


if __name__ == "__main__":
    unittest.main()
