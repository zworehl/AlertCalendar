import importlib.util
from pathlib import Path
import sys
import unittest
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("report_coverage", Path(__file__).with_name("report_coverage.py"))
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class CoverageReportTests(unittest.TestCase):
    def testWholeSourceReportDoesNotHideUngatedCodeOrIncludeTests(self):
        root = Path("/tmp/coverage-test-root")
        def entry(relative, count, covered):
            return {"filename": str(root / relative), "summary": {"lines": {"count": count, "covered": covered}}}
        files = coverage.source_metrics({"data": [{"files": [
            entry("Sources/AlertCalendar/Shared/A.swift", 10, 10),
            entry("Sources/AlertCalendar/Core/B.swift", 90, 0),
            entry("Tests/AlertCalendarTests/Test.swift", 100, 100),
        ]}]}, root)
        self.assertEqual(coverage.totals(files)["percent"], 10)
        self.assertTrue(coverage.evaluate_gate(files, "foundation", 97,
                        ["Sources/AlertCalendar/Shared/A.swift"])["passed"])

    def testRiskGateFailsIndependentlyOfOtherCoverage(self):
        files = {"Sources/AlertCalendar/Core/Network.swift": {"count": 100, "covered": 79}}
        self.assertFalse(coverage.evaluate_gate(files, "transport", 80, list(files))["passed"])

    def testMissingOrZeroLineGateCannotSilentlyPass(self):
        files = {"Sources/AlertCalendar/Empty.swift": {"count": 0, "covered": 0}}
        for patterns in (["missing.swift"], list(files)):
            with self.subTest(patterns=patterns), self.assertRaises(ValueError):
                coverage.evaluate_gate(files, "risk", 90, patterns)

    def testOverlappingPatternsDoNotDoubleCountLines(self):
        files = {"Sources/AlertCalendar/Core/A.swift": {"count": 10, "covered": 9},
                 "Sources/AlertCalendar/Core/B.swift": {"count": 20, "covered": 10}}
        gate = coverage.evaluate_gate(files, "core", 60,
                ["Sources/AlertCalendar/Core/*", "Sources/AlertCalendar/Core/A.swift"])
        self.assertEqual((gate["count"], gate["covered"]), (30, 19))


if __name__ == "__main__":
    unittest.main()
