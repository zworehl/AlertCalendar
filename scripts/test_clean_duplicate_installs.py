import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True


spec = importlib.util.spec_from_file_location(
    "cleanup", Path(__file__).with_name("clean_duplicate_installs.py")
)
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class DuplicateInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.keep = self.bundle("Applications/AlertCalendar.app", "com.zworehl.alertcalendar")

    def bundle(self, path, identifier):
        bundle = self.root / path
        (bundle / "Contents").mkdir(parents=True)
        with (bundle / "Contents/Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": identifier}, file)
        return bundle

    def testRemovesRenamedAndNestedCopiesAndKeepsUnrelatedApplications(self):
        duplicate = self.bundle("tmp/release/LocalizationQA.app", "com.zworehl.alertcalendar")
        legacy = self.bundle("Applications/AlertCalendar old.app", "com.alertcalendar.app")
        unrelated = self.bundle("Other/AlertCalendar.app", "com.example.unrelated")
        embedded = self.bundle("Other/AlertCalendar.app/Contents/Helper.app", "com.zworehl.alertcalendar")
        with patch.object(cleanup, "LSREGISTER", self.root / "missing-lsregister"):
            cleanup.clean_duplicates([self.root], self.keep,
                                     {"com.zworehl.alertcalendar", "com.alertcalendar.app"})
        self.assertTrue(self.keep.is_dir())
        self.assertTrue(unrelated.is_dir())
        self.assertTrue(embedded.is_dir())
        self.assertFalse(duplicate.exists())
        self.assertFalse(legacy.exists())

    def testSymlinksAndMalformedBundlesArePreserved(self):
        alias = self.root / "alias.app"
        alias.symlink_to(self.keep, target_is_directory=True)
        malformed = self.root / "broken.app/Contents"
        malformed.mkdir(parents=True)
        (malformed / "Info.plist").write_text("invalid")
        self.assertEqual(list(cleanup.duplicate_bundles(
            [self.root], alias, {"com.zworehl.alertcalendar"}
        )), [])

    def testOverlappingSearchDirectoriesYieldEachDuplicateOnce(self):
        duplicate = self.bundle("tmp/Release.app", "com.zworehl.alertcalendar")
        self.assertEqual(list(cleanup.duplicate_bundles(
            [self.root, self.root / "tmp"], self.keep, {"com.zworehl.alertcalendar"}
        )), [duplicate])


if __name__ == "__main__":
    unittest.main()
