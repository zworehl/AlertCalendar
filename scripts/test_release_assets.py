import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_assets", Path(__file__).with_name("release_assets.py"))
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class ReleaseAssetTests(unittest.TestCase):
    def testChangedArchiveCannotReplacePublishedAsset(self):
        with self.assertRaisesRegex(ValueError, "immutable"):
            assets.immutable_upload_plan({"app.zip": "old"}, {"app.zip": "new"})

    def testIdenticalRerunAndMissingAssetsAreIdempotent(self):
        self.assertEqual(assets.immutable_upload_plan({"app.zip": "same"}, {"app.zip": "same"}), [])
        self.assertEqual(assets.immutable_upload_plan({"app.zip": "same", "unrelated": "kept"},
                         {"app.zip": "same", "checksum": "new"}), ["checksum"])

    def testAppcastUsesImmutableGitHubURLsWithoutChangingSignature(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
                            '<sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>'
                            '<enclosure url="https://example.test/app.zip" sparkle:edSignature="original-signature" />'
                            '</item></channel></rss>')
            assets.use_canonical_downloads(path, "owner/repo")
            enclosure = ET.parse(path).find("./channel/item/enclosure")
            self.assertEqual(enclosure.get("url"), "https://github.com/owner/repo/releases/download/v1.2.0/AlertCalendar-1.2.0.zip")
            self.assertEqual(enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"), "original-signature")

    def testChangedPublishedContentFailsBeforeAnyUpload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "app.zip").write_bytes(b"new")
            def old_asset(_repo, _asset, destination):
                (destination / "app.zip").write_bytes(b"old")
            with patch.object(assets, "gh_json", return_value={"assets": [{"id": 1, "name": "app.zip"}]}), \
                 patch.object(assets, "download_asset", side_effect=old_asset), \
                 patch.object(assets.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    assets.publish("owner/repo", "v1", path, ["app.zip"], "title", path / "notes.md")
                run.assert_not_called()

    def testRetainingArchivesDoesNotReplaceCandidateOrDownloadDrafts(self):
        releases = [{"draft": True, "tag_name": "v3", "assets": [{"name": "AlertCalendar-3.zip", "id": 3}]},
                    {"tag_name": "v2", "assets": [{"name": "AlertCalendar-2.zip", "id": 2}]},
                    {"tag_name": "v1", "assets": [{"name": "AlertCalendar-1.zip", "id": 1},
                                                    {"name": "appcast.xml", "id": 11}]}]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "AlertCalendar-2.zip").write_bytes(b"candidate")
            (path / "appcast.xml").write_text('<rss><channel /></rss>')
            def retain(_repo, asset, destination):
                if asset["name"] == "appcast.xml":
                    (destination / "appcast.xml").write_text(
                        '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
                        '<sparkle:shortVersionString>1</sparkle:shortVersionString>'
                        '<enclosure sparkle:edSignature="previous-signature" /></item></channel></rss>')
                else:
                    (destination / asset["name"]).write_bytes(b"previous")
            with patch.object(assets, "gh_json", return_value=releases), \
                 patch.object(assets, "download_asset", side_effect=retain) as download:
                assets.retain_archives("owner/repo", "v2", path)
                self.assertEqual(download.call_count, 2)
                self.assertEqual((path / "AlertCalendar-2.zip").read_bytes(), b"candidate")
                self.assertEqual((path / "AlertCalendar-1.zip").read_bytes(), b"previous")
                enclosure = ET.parse(path / "appcast.xml").find("./channel/item/enclosure")
                self.assertEqual(enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"), "previous-signature")


if __name__ == "__main__":
    unittest.main()
