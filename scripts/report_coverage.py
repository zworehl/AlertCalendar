#!/usr/bin/env python3
"""Report all application coverage separately from explicit gradual risk gates."""
from __future__ import annotations
import argparse
import fnmatch
import json
from pathlib import Path
import subprocess
import sys


def source_metrics(export: dict, root: Path) -> dict[str, dict]:
    source_root = (root / "Sources/AlertCalendar").resolve()
    files = {}
    for group in export.get("data", []):
        for entry in group.get("files", []):
            path = Path(entry["filename"]).resolve()
            if path.suffix != ".swift" or not path.is_relative_to(source_root):
                continue
            lines = entry["summary"]["lines"]
            files[str(path.relative_to(root.resolve()))] = {
                "count": int(lines["count"]), "covered": int(lines["covered"])}
    if not files:
        raise ValueError("The profile contains no application source files.")
    return files


def totals(files: dict[str, dict]) -> dict:
    count = sum(file["count"] for file in files.values())
    covered = sum(file["covered"] for file in files.values())
    return {"count": count, "covered": covered, "percent": 100 * covered / count if count else 100.0}


def evaluate_gate(files: dict[str, dict], name: str, minimum: float, patterns: list[str]) -> dict:
    if not 0 <= minimum <= 100 or not patterns:
        raise ValueError(f"Invalid coverage gate: {name}")
    selected = {}
    for pattern in patterns:
        matched = {path: lines for path, lines in files.items() if fnmatch.fnmatchcase(path, pattern)}
        if not matched:
            raise ValueError(f"Gate {name!r} has no instrumented files matching {pattern!r}.")
        selected.update(matched)
    measured = totals(selected)
    if not measured["count"]:
        raise ValueError(f"Gate {name!r} contains no executable lines.")
    return {"name": name, "minimum": minimum, "files": sorted(selected), **measured,
            "passed": measured["percent"] + 1e-9 >= minimum}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--foundation-min", type=float, required=True)
    parser.add_argument("--foundation-file", action="append", default=[])
    parser.add_argument("--risk-gate", action="append", default=[], help="name|minimum|file[,file...]")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = subprocess.run(["xcrun", "llvm-cov", "export", str(args.binary), "-instr-profile",
                                 str(args.profile), "-summary-only"], capture_output=True, text=True, check=True)
        files = source_metrics(json.loads(result.stdout), args.root)
        gates = [evaluate_gate(files, "Foundation (selected files)", args.foundation_min, args.foundation_file)]
        for spec in args.risk_gate:
            name, minimum, paths = spec.split("|", 2)
            gates.append(evaluate_gate(files, name, float(minimum), paths.split(",")))
        overall = totals(files)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"overall": overall, "gates": gates, "files": files},
                                         indent=2, sort_keys=True) + "\n")
        print(f"Whole application: {overall['percent']:.2f}% ({overall['covered']}/{overall['count']} instrumented lines); reported, not a global gate.")
        for gate in gates:
            status = "passed" if gate["passed"] else "FAILED"
            print(f"{gate['name']} gate {status}: {gate['percent']:.2f}% >= {gate['minimum']:g}% ({len(gate['files'])} files)")
        print(f"Detailed coverage report: {args.output}")
        return 0 if all(gate["passed"] for gate in gates) else 1
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Coverage reporting failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
