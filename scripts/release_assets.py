#!/usr/bin/env python3
"""Keep released archives immutable and retain a usable multi-version update channel."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET


def digest(path: Path) -> str:
    with path.open("rb") as file:
        checksum = hashlib.sha256()
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            checksum.update(chunk)
        return checksum.hexdigest()


def immutable_upload_plan(existing: dict[str, str], candidates: dict[str, str]) -> list[str]:
    changed = [name for name, checksum in candidates.items()
               if name in existing and existing[name] != checksum]
    if changed:
        raise ValueError(f"Published assets are immutable; use a new version/build/tag: {', '.join(changed)}")
    return [name for name in candidates if name not in existing]


def gh_json(arguments: list[str], *, missing_ok: bool = False):
    result = subprocess.run(["gh", *arguments], capture_output=True, text=True)
    if result.returncode:
        if missing_ok and "HTTP 404" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or "GitHub CLI failed.")
    return json.loads(result.stdout)


def download_asset(repo: str, asset: dict, destination: Path) -> None:
    name = asset["name"]
    if Path(name).name != name or name in (".", ".."):
        raise ValueError("A release asset has an unsafe filename.")
    with (destination / name).open("wb") as file:
        subprocess.run(["gh", "api", f"repos/{repo}/releases/assets/{int(asset['id'])}",
                        "-H", "Accept: application/octet-stream"], stdout=file, check=True)


def retain_archives(repo: str, tag: str, directory: Path, keep: int = 2) -> None:
    releases = gh_json(["api", f"repos/{repo}/releases?per_page=20"])
    current_appcast = directory / "appcast.xml"
    tree = ET.parse(current_appcast)
    channel = tree.find("channel")
    if channel is None:
        raise ValueError("The new appcast has no channel.")
    sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    retained = 0
    for release in releases:
        if release.get("draft") or release.get("tag_name") == tag:
            continue
        assets = [asset for asset in release.get("assets", [])
                  if asset["name"].startswith("AlertCalendar-")
                  and (asset["name"].endswith(".zip") or asset["name"].endswith(".zip.sha256"))]
        if not any(asset["name"].endswith(".zip") for asset in assets):
            continue
        appcast_asset = next((asset for asset in release.get("assets", []) if asset["name"] == "appcast.xml"), None)
        if appcast_asset is None:
            raise ValueError(f"Release {release.get('tag_name')} has no signed update metadata to retain.")
        # Merge already-signed metadata after generate_appcast, never re-sign a
        # downloaded archive with the current workflow's private signing key.
        with tempfile.TemporaryDirectory(prefix="alertcalendar-retained-feed-") as temporary:
            previous = Path(temporary)
            download_asset(repo, appcast_asset, previous)
            version = release["tag_name"].removeprefix("v")
            items = []
            for item in ET.parse(previous / "appcast.xml").findall("./channel/item"):
                enclosure = item.find("enclosure")
                item_version = item.findtext(f"{{{sparkle}}}shortVersionString")
                if enclosure is not None:
                    item_version = enclosure.get(f"{{{sparkle}}}shortVersionString") or item_version
                if item_version == version:
                    items.append(item)
            if not items:
                raise ValueError(f"Release {release['tag_name']} has no matching signed appcast item.")
            for item in items:
                channel.append(item)
        for asset in assets:
            if (directory / asset["name"]).exists():
                raise ValueError(f"A retained release would overwrite {asset['name']}.")
            download_asset(repo, asset, directory)
        retained += 1
        if retained >= keep:
            break
    ET.register_namespace("sparkle", sparkle)
    tree.write(current_appcast, encoding="utf-8", xml_declaration=True)


def use_canonical_downloads(appcast: Path, repo: str) -> None:
    tree = ET.parse(appcast)
    sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", sparkle)
    for item in tree.findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        version = enclosure.get(f"{{{sparkle}}}shortVersionString")
        if version is None:
            version = item.findtext(f"{{{sparkle}}}shortVersionString")
        if not version:
            raise ValueError("The appcast item has no public version for its immutable download URL.")
        name = f"AlertCalendar-{version}.zip"
        enclosure.set("url", f"https://github.com/{repo}/releases/download/{quote('v' + version, safe='')}/{quote(name, safe='')}")
    tree.write(appcast, encoding="utf-8", xml_declaration=True)


def publish(repo: str, tag: str, directory: Path, names: list[str], title: str, notes: Path) -> None:
    candidates = {name: digest(directory / name) for name in names}
    release = gh_json(["api", f"repos/{repo}/releases/tags/{quote(tag, safe='')}"], missing_ok=True)
    if release is None:
        subprocess.run(["gh", "release", "create", tag, "--repo", repo, "--verify-tag", "--title", title,
                        "--notes-file", str(notes), *[str(directory / name) for name in names]], check=True)
        return
    with tempfile.TemporaryDirectory(prefix="alertcalendar-release-check-") as temporary:
        previous = Path(temporary)
        existing = {}
        for asset in release.get("assets", []):
            if asset["name"] in candidates:
                download_asset(repo, asset, previous)
                existing[asset["name"]] = digest(previous / asset["name"])
        missing = immutable_upload_plan(existing, candidates)
    if missing:
        # Without --clobber GitHub also protects against a concurrent name collision.
        subprocess.run(["gh", "release", "upload", tag, "--repo", repo,
                        *[str(directory / name) for name in missing]], check=True)
    else:
        print("Published assets match; nothing was overwritten.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("retain", "canonicalize", "publish"))
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag")
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--asset", action="append", default=[])
    parser.add_argument("--title", default="AlertCalendar")
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "retain":
            retain_archives(args.repo, args.tag, args.directory)
        elif args.action == "canonicalize":
            use_canonical_downloads(args.directory / "appcast.xml", args.repo)
        else:
            if not args.tag or not args.asset or not args.notes:
                raise ValueError("Publish requires --tag, --asset and --notes.")
            publish(args.repo, args.tag, args.directory, args.asset, args.title, args.notes)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, ET.ParseError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
