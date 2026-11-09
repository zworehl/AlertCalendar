#!/usr/bin/env python3
"""Remove this application's bundles without descending into other apps."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


LSREGISTER = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)


def duplicate_bundles(search_dirs, keep, bundle_identifiers):
    keep = Path(keep).resolve()
    seen = set()
    for search_dir in search_dirs:
        for parent, directories, _ in os.walk(search_dir, followlinks=False):
            for name in list(directories):
                if not name.lower().endswith(".app"):
                    continue
                directories.remove(name)
                bundle = Path(parent) / name
                if bundle.is_symlink() or bundle.resolve() == keep or bundle in seen:
                    continue
                seen.add(bundle)
                try:
                    with (bundle / "Contents/Info.plist").open("rb") as file:
                        metadata = plistlib.load(file)
                        identifier = metadata.get("CFBundleIdentifier") if isinstance(metadata, dict) else None
                except (OSError, ValueError, plistlib.InvalidFileException):
                    continue
                if identifier in bundle_identifiers:
                    yield bundle


def clean_duplicates(search_dirs, keep, bundle_identifiers):
    for bundle in duplicate_bundles(search_dirs, keep, bundle_identifiers):
        print(f"Removing duplicate install: {bundle}", flush=True)
        if LSREGISTER.is_file():
            subprocess.run([str(LSREGISTER), "-u", str(bundle)], check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(bundle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", required=True)
    parser.add_argument("--bundle-identifier", action="append", required=True)
    parser.add_argument("--search-dir", action="append", required=True)
    args = parser.parse_args()
    clean_duplicates(args.search_dir, args.keep, set(args.bundle_identifier))


if __name__ == "__main__":
    main()
