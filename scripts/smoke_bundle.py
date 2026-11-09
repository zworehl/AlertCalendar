#!/usr/bin/env python3
"""Validate a signed app bundle and exercise its isolated, offline UI smoke session."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile


class BundleSmokeError(RuntimeError):
    pass


def validate_report(report: object) -> list[dict]:
    if not isinstance(report, dict) or report.get("passed") is not True:
        raise BundleSmokeError(f"The app smoke session did not pass: {report}")
    checks = report.get("checks")
    if not isinstance(checks, list) or not checks:
        raise BundleSmokeError("The smoke report contains no checks.")
    if any(not isinstance(check, dict) or not check.get("name") or check.get("passed") is not True
           for check in checks):
        raise BundleSmokeError(f"The smoke report contains a failed or malformed check: {checks}")
    return checks


def validate_layout(bundle: Path) -> Path:
    info_path = bundle / "Contents/Info.plist"
    with info_path.open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundleIdentifier") != "com.zworehl.alertcalendar":
        raise BundleSmokeError("The bundle identifier does not match AlertCalendar.")
    for key in ("CFBundleVersion", "CFBundleShortVersionString", "NSCalendarsUsageDescription",
                "NSRemindersUsageDescription", "NSAppleEventsUsageDescription"):
        if not info.get(key):
            raise BundleSmokeError(f"The app bundle is missing {key}.")
    resources = bundle / "Contents/Resources"
    for path in (resources / "AlertCalendar_AlertCalendar.bundle", resources / "Metadata.appintents",
                 bundle / "Contents/Frameworks/Sparkle.framework"):
        if not path.is_dir():
            raise BundleSmokeError(f"The app bundle is missing {path.relative_to(bundle)}.")
    executable = bundle / "Contents/MacOS/AlertCalendar"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise BundleSmokeError("The app executable is missing or is not executable.")
    return executable


def run_session(executable: Path, report: Path, timeout: float) -> list[dict]:
    process = subprocess.Popen(
        [str(executable), "--smoke-test", "--report", str(report)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise BundleSmokeError(f"The isolated smoke session exceeded {timeout:g} seconds.") from error
    if process.returncode != 0:
        details = (stderr or stdout)[-2000:]
        if report.is_file():
            try:
                payload = json.loads(report.read_text())
                checks = payload.get("checks", []) if isinstance(payload, dict) else []
                failed = []
                for check in checks if isinstance(checks, list) else []:
                    if isinstance(check, dict) and check.get("passed") is not True:
                        name = str(check.get("name", "unnamed check"))
                        message = str(check.get("detail") or check.get("message") or "")
                        failed.append(f"{name}: {message}" if message else name)
                if failed:
                    details = f"Failed checks: {'; '.join(failed)[:4000]}. {details}"
                elif isinstance(payload, dict):
                    details = f"Report passed={payload.get('passed')!r}; no failed check details. {details}"
            except (OSError, ValueError) as error:
                details = f"The smoke report was unreadable: {error}. {details}"
        raise BundleSmokeError(f"The isolated smoke session exited {process.returncode}: {details}")
    try:
        return validate_report(json.loads(report.read_text()))
    except (OSError, ValueError) as error:
        raise BundleSmokeError(f"The app did not produce a readable smoke report: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        executable = validate_layout(args.bundle.absolute())
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(args.bundle)],
                       check=True, timeout=30)
        with tempfile.TemporaryDirectory(prefix="alertcalendar-smoke-") as directory:
            report_path = Path(directory) / "report.json"
            try:
                checks = run_session(executable, report_path, args.timeout)
            finally:
                if args.report and report_path.is_file():
                    args.report.parent.mkdir(parents=True, exist_ok=True)
                    args.report.write_bytes(report_path.read_bytes())
        print(f"Bundle smoke passed: {len(checks)} isolated checks.")
    except (BundleSmokeError, OSError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
