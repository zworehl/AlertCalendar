#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-$ROOT_DIR/coverage-gate.conf}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Coverage config not found: $CONFIG_PATH" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_PATH"

if [[ -z "${MIN_LINE_COVERAGE:-}" ]]; then
  echo "MIN_LINE_COVERAGE is required in $CONFIG_PATH" >&2
  exit 1
fi

if ! declare -p INCLUDE_FILES >/dev/null 2>&1; then
  echo "INCLUDE_FILES is required in $CONFIG_PATH" >&2
  exit 1
fi

if [[ ${#INCLUDE_FILES[@]} -eq 0 ]]; then
  echo "INCLUDE_FILES must include at least one source file in $CONFIG_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift test --enable-code-coverage

PROFDATA="$(find .build -type f -name default.profdata | head -n 1)"
if [[ -z "$PROFDATA" ]]; then
  echo "Coverage profile not found (.build/**/default.profdata)." >&2
  exit 1
fi

TEST_BINARY="$(find .build -type f -path "*/debug/*PackageTests.xctest/Contents/MacOS/*PackageTests" -not -path "*.dSYM/*" | head -n 1)"
if [[ -z "$TEST_BINARY" ]]; then
  echo "Package test binary not found in .build." >&2
  exit 1
fi

ABS_FILES=()
for rel_path in "${INCLUDE_FILES[@]}"; do
  abs_path="$ROOT_DIR/$rel_path"
  if [[ ! -f "$abs_path" ]]; then
    echo "Configured source file not found: $rel_path" >&2
    exit 1
  fi
  ABS_FILES+=("$abs_path")
done

REPORT="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" "${ABS_FILES[@]}")"
echo "$REPORT"

LINE_COVERAGE="$(printf "%s\n" "$REPORT" | awk '/TOTAL/ { gsub("%", "", $10); print $10 }')"
if [[ -z "$LINE_COVERAGE" ]]; then
  echo "Unable to parse total line coverage from llvm-cov output." >&2
  exit 1
fi

if awk -v value="$LINE_COVERAGE" -v min="$MIN_LINE_COVERAGE" 'BEGIN { exit !(value + 0 >= min + 0) }'; then
  echo "Coverage gate passed: ${LINE_COVERAGE}% >= ${MIN_LINE_COVERAGE}%"
else
  echo "Coverage gate failed: ${LINE_COVERAGE}% < ${MIN_LINE_COVERAGE}%" >&2
  exit 1
fi
