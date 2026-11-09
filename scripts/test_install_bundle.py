import importlib.util
from pathlib import Path
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("install_bundle", Path(__file__).with_name("install_bundle.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class BundleTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bundle transaction ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.staged = self.bundle("custom Applications/.AlertCalendar.install.test/AlertCalendar.app", "new")
        self.target = self.bundle("custom Applications/AlertCalendar.app", "old")
        self.unrelated = self.bundle("custom Applications/Unrelated.app", "unrelated")

    def bundle(self, name, content):
        path = self.root / name
        path.mkdir(parents=True)
        (path / "version").write_text(content)
        return path

    def install(self, **kwargs):
        installer.install_bundle(self.staged, self.target, validate=lambda _: None, **kwargs)

    def testValidationFailureKeepsRunningInstallationAndStagedFilesUntouched(self):
        def reject(_):
            raise RuntimeError("bad signature")
        with self.assertRaisesRegex(RuntimeError, "bad signature"):
            installer.install_bundle(self.staged, self.target, validate=reject)
        self.assertEqual((self.target / "version").read_text(), "old")
        self.assertTrue(self.staged.exists())

    def testSuccessfulActivationCommitsNewBundleAndRemovesBackup(self):
        observed = []
        self.install(activate=lambda path: observed.append((path / "version").read_text()))
        self.assertEqual(observed, ["new"])
        self.assertEqual((self.target / "version").read_text(), "new")
        self.assertFalse((self.staged.parent / "previous.app").exists())
        self.assertEqual((self.unrelated / "version").read_text(), "unrelated")

    def testCandidateRenameFailureRestoresPreviousBundle(self):
        replace = os.replace
        def fail_candidate(source, destination):
            if Path(source) == self.staged:
                raise OSError("disk error")
            replace(source, destination)
        with patch.object(installer.os, "replace", side_effect=fail_candidate):
            with self.assertRaisesRegex(installer.BundleInstallError, "restored"):
                self.install()
        self.assertEqual((self.target / "version").read_text(), "old")

    def testLaunchFailureStopsCandidateAndRestoresPreviousBundle(self):
        stopped = []
        def fail_launch(_):
            raise RuntimeError("launch failed")
        with self.assertRaisesRegex(installer.BundleInstallError, "restored"):
            self.install(activate=fail_launch, stop=lambda path: stopped.append(path))
        self.assertEqual(stopped, [self.target])
        self.assertEqual((self.target / "version").read_text(), "old")
        self.assertEqual((self.staged.parent / "failed.app/version").read_text(), "new")

    def testRollbackFailureRetainsTheOnlyPreviousBundle(self):
        replace = os.replace
        def fail_restore(source, destination):
            if Path(source).name == "previous.app":
                raise OSError("restore denied")
            replace(source, destination)
        def fail_launch(_):
            raise RuntimeError("launch failed")
        with patch.object(installer.os, "replace", side_effect=fail_restore):
            with self.assertRaisesRegex(installer.BundleInstallError, "preserved at"):
                self.install(activate=fail_launch)
        self.assertEqual((self.staged.parent / "previous.app/version").read_text(), "old")
        self.assertEqual((self.unrelated / "version").read_text(), "unrelated")

    def testFirstInstallFailureDoesNotLeaveUnverifiedApplication(self):
        import shutil
        shutil.rmtree(self.target)
        def fail_launch(_):
            raise RuntimeError("launch failed")
        with self.assertRaises(installer.BundleInstallError):
            self.install(activate=fail_launch)
        self.assertFalse(self.target.exists())
        self.assertTrue((self.staged.parent / "failed.app").exists())


if __name__ == "__main__":
    unittest.main()
