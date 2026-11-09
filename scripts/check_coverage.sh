#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT_DIR/coverage-gate.conf"
RUN_TESTS=1
for argument in "$@"; do
  if [[ "$argument" == "--skip-tests" ]]; then RUN_TESTS=0
  else CONFIG_PATH="$argument"; fi
done
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Coverage config not found: $CONFIG_PATH" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_PATH"
: "${MIN_LINE_COVERAGE:?MIN_LINE_COVERAGE is required}"
if ! declare -p INCLUDE_FILES >/dev/null 2>&1 || [[ ${#INCLUDE_FILES[@]} -eq 0 ]]; then
  echo "INCLUDE_FILES must contain the selected foundation files." >&2
  exit 1
fi
cd "$ROOT_DIR"
if [[ "$RUN_TESTS" == "1" ]]; then
  SWIFT_TEST_ARGS=(test --enable-code-coverage)
  if [[ -n "${SWIFT_TEST_JOBS:-}" ]]; then SWIFT_TEST_ARGS+=(--jobs "$SWIFT_TEST_JOBS"); fi
  swift "${SWIFT_TEST_ARGS[@]}"
fi
# Select this configuration's outputs, never an arbitrary stale DerivedData profile.
BIN_DIR="$(swift build --show-bin-path)"
PROFILE="${COVERAGE_PROFILE:-$BIN_DIR/codecov/default.profdata}"
TEST_BINARY="$(python3 - "$BIN_DIR" <<'PY'
from pathlib import Path
import sys
matches = [path for path in Path(sys.argv[1]).glob('*.xctest/Contents/MacOS/*') if path.is_file()]
if len(matches) != 1:
    raise SystemExit(f'Expected one test binary in {sys.argv[1]}, found {len(matches)}')
print(matches[0])
PY
)"
if [[ ! -f "$PROFILE" ]]; then
  echo "Coverage profile not found: $PROFILE" >&2
  exit 1
fi
REPORT_ARGS=(--root "$ROOT_DIR" --binary "$TEST_BINARY" --profile "$PROFILE"
  --foundation-min "$MIN_LINE_COVERAGE" --output "$ROOT_DIR/.build/coverage-report.json")
for path in "${INCLUDE_FILES[@]}"; do REPORT_ARGS+=(--foundation-file "$path"); done
if declare -p RISK_GATES >/dev/null 2>&1; then
  for gate in "${RISK_GATES[@]}"; do REPORT_ARGS+=(--risk-gate "$gate"); done
fi
python3 "$ROOT_DIR/scripts/report_coverage.py" "${REPORT_ARGS[@]}"
