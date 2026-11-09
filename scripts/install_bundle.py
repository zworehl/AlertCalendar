#!/usr/bin/env python3
"""Commit an already prepared app bundle, retaining the previous app until activation succeeds."""
from __future__ import annotations

import argparse
from pathlib import Path
import os
import signal
import subprocess
import sys
import time
from typing import Callable


class BundleInstallError(RuntimeError):
    pass


def matching_processes(bundle: Path) -> list[int]:
    executable = str(bundle / "Contents/MacOS/AlertCalendar")
    result = subprocess.run(["/bin/ps", "-axo", "pid=,command="], check=True,
                            capture_output=True, text=True)
    matches = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == executable:
            matches.append(int(parts[0]))
    return matches


def stop_bundle(bundle: Path) -> None:
    pids = matching_processes(bundle)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and any(pid in matching_processes(bundle) for pid in pids):
        time.sleep(0.1)
    for pid in pids:
        if pid in matching_processes(bundle):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def launch_bundle(bundle: Path, timeout: float = 10, stable_for: float = 3) -> None:
    subprocess.run(["/usr/bin/open", str(bundle)], check=True, timeout=timeout)
    deadline = time.monotonic() + timeout
    alive_since = None
    while time.monotonic() < deadline:
        if matching_processes(bundle):
            alive_since = alive_since or time.monotonic()
            if time.monotonic() - alive_since >= stable_for:
                return
        elif alive_since is not None:
            raise BundleInstallError("The new application exited during launch verification.")
        time.sleep(0.2)
    raise BundleInstallError("The new application did not become ready before the launch deadline.")


def install_bundle(
    staged: Path,
    target: Path,
    *,
    validate: Callable[[Path], None],
    activate: Callable[[Path], None] | None = None,
    stop: Callable[[Path], None] | None = None,
) -> None:
    """Rename on one filesystem; rollback never deletes the only remaining previous bundle."""
    staged = staged.absolute()
    target = target.absolute()
    if staged == target or not staged.is_dir() or staged.is_symlink():
        raise BundleInstallError("Expected a separate, prepared application directory.")
    if staged.stat().st_dev != target.parent.stat().st_dev:
        raise BundleInstallError("Staging and destination must be on the same filesystem.")
    backup = staged.parent / "previous.app"
    failed = staged.parent / "failed.app"
    if backup.exists() or failed.exists():
        raise BundleInstallError("The transaction directory already contains recovery files.")
    validate(staged)
    had_previous = target.exists() or target.is_symlink()
    moved_previous = False
    committed_candidate = False
    try:
        if had_previous:
            os.replace(target, backup)
            moved_previous = True
        os.replace(staged, target)
        committed_candidate = True
        if activate is not None:
            activate(target)
    except BaseException as failure:
        try:
            if committed_candidate:
                if stop is not None:
                    stop(target)
                os.replace(target, failed)
            if moved_previous:
                os.replace(backup, target)
        except BaseException as rollback_failure:
            raise BundleInstallError(
                f"Installation failed and automatic recovery could not finish. "
                f"The previous bundle is preserved at {backup}. "
                f"Original failure: {failure}; recovery failure: {rollback_failure}"
            ) from rollback_failure
        recovery = "the previous application was restored" if had_previous else "the unverified candidate was removed"
        raise BundleInstallError(f"Installation failed; {recovery}: {failure}") from failure
    if moved_previous:
        import shutil
        try:
            if backup.is_symlink():
                backup.unlink()
            else:
                shutil.rmtree(backup)
        except OSError as error:
            print(f"The new app is active. The previous bundle remains at {backup}: {error}", file=sys.stderr)


def main() -> int:
    def interrupted(_signal, _frame):
        raise InterruptedError("Installation was interrupted.")
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--launch", action="store_true")
    args = parser.parse_args()
    try:
        install_bundle(
            args.staged, args.target,
            validate=lambda bundle: subprocess.run(
                ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)], check=True),
            activate=launch_bundle if args.launch else None,
            stop=stop_bundle if args.launch else None,
        )
    except (BundleInstallError, OSError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
