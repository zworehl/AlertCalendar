#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
./scripts/check_architecture.sh
python3 ./scripts/check_localization.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py'
./scripts/check_coverage.sh

# Package validation uses an isolated bundle and the app's offline smoke CLI.
# It never stops the installed app or requests access to user calendars/accounts.
if [[ "${VERIFY_BUNDLE:-1}" == "1" ]]; then
  VALIDATION_PACKAGE_DIR="$(mktemp -d)"
  trap 'rm -rf "$VALIDATION_PACKAGE_DIR"' EXIT
  APP_DIR="$VALIDATION_PACKAGE_DIR" \
  CODE_SIGN_IDENTITY="${VERIFY_CODE_SIGN_IDENTITY:--}" \
  OPEN_AFTER_INSTALL=0 REMOVE_DUPLICATE_INSTALLS=0 TERMINATE_RUNNING_INSTANCES=0 \
  CLEAN_BUILD=0 DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/.build/install-derived-data}" \
    ./install.sh
fi
