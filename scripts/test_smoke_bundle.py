import importlib.util
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("smoke_bundle", Path(__file__).with_name("smoke_bundle.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class BundleSmokeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bundle smoke ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def executable(self, code):
        path = self.root / "fake app"
        path.write_text(f"#!{sys.executable}\n" + code)
        path.chmod(0o755)
        return path

    def testSuccessRequiresStructuredChecksRatherThanOnlyAZeroExit(self):
        executable = self.executable(
            "import json,sys\nfrom pathlib import Path\n"
            "Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps("
            "{'passed':True,'checks':[{'name':'settings','passed':True}]}))\n"
        )
        checks = smoke.run_session(executable, self.root / "report.json", 2)
        self.assertEqual(checks[0]["name"], "settings")

    def testZeroExitWithoutAReportFails(self):
        with self.assertRaisesRegex(smoke.BundleSmokeError, "readable smoke report"):
            smoke.run_session(self.executable("pass\n"), self.root / "missing.json", 2)

    def testFailedOrEmptyChecksCannotBeHiddenBehindPassedFlag(self):
        for checks in ([], [{"name": "settings", "passed": False}], [{"passed": True}]):
            with self.subTest(checks=checks):
                with self.assertRaises(smoke.BundleSmokeError):
                    smoke.validate_report({"passed": True, "checks": checks})

    def testTimeoutTerminatesTheSession(self):
        started = time.monotonic()
        with self.assertRaisesRegex(smoke.BundleSmokeError, "exceeded"):
            smoke.run_session(self.executable("import time\ntime.sleep(20)\n"), self.root / "report.json", 0.1)
        self.assertLess(time.monotonic() - started, 3)

    def testNonzeroExitFailsEvenWhenReportSaysPassed(self):
        executable = self.executable(
            "import json,sys\nfrom pathlib import Path\n"
            "Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps("
            "{'passed':True,'checks':[{'name':'settings','passed':True}]}))\nraise SystemExit(3)\n"
        )
        with self.assertRaisesRegex(smoke.BundleSmokeError, "exited 3"):
            smoke.run_session(executable, self.root / "report.json", 2)

    def failed_session(self):
        return self.executable(
            "import json,sys\nfrom pathlib import Path\n"
            "Path(sys.argv[sys.argv.index('--report')+1]).write_text(json.dumps("
            "{'passed':False,'checks':[{'name':'settings-narrow-es','passed':False,'detail':'unexpected overflow'}]}))\n"
            "raise SystemExit(1)\n"
        )

    def testNonzeroExitReportsFailedCheckFromJSONWhenStderrIsEmpty(self):
        with self.assertRaisesRegex(smoke.BundleSmokeError, "settings-narrow-es: unexpected overflow"):
            smoke.run_session(self.failed_session(), self.root / "report.json", 2)

    def testRequestedReportIsPreservedWhenSessionFails(self):
        destination = self.root / "retained diagnostics/report.json"
        executable = self.failed_session()
        with patch.object(sys, "argv", ["smoke_bundle.py", str(self.root / "app"), "--report", str(destination)]), \
             patch.object(smoke, "validate_layout", return_value=executable), \
             patch.object(smoke.subprocess, "run"), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(smoke.main(), 1)
        report = json.loads(destination.read_text())
        self.assertFalse(report["passed"])
        self.assertEqual(report["checks"][0]["name"], "settings-narrow-es")


if __name__ == "__main__":
    unittest.main()
