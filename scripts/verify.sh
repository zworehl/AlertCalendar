#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

./scripts/check_architecture.sh
python3 ./scripts/check_localization.py
./scripts/check_coverage.sh
xcodebuild \
  -scheme AlertCalendar \
  -configuration Release \
  -destination "platform=macOS" \
  build
