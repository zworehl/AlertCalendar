#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AlertCalendar"
BINARY_NAME="AlertCalendar"
APP_DIR="${APP_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-1}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer supports macOS only."
  exit 1
fi

echo "[1/3] Building ${APP_NAME} (release)..."
swift build -c release --package-path "$ROOT"

BINARY_PATH="$(find "$ROOT/.build" -type f -path "*/release/${BINARY_NAME}" | head -n 1)"
if [[ -z "$BINARY_PATH" ]]; then
  echo "Unable to locate built binary: ${BINARY_NAME}"
  exit 1
fi

APP_BUNDLE="$APP_DIR/${APP_NAME}.app"

echo "[2/3] Installing to ${APP_BUNDLE}..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.zworehl.alertcalendar</string>
  <key>CFBundleExecutable</key>
  <string>${BINARY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_BUNDLE" || true
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "[3/3] Done."
echo "Installed: $APP_BUNDLE"

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  open "$APP_BUNDLE" || true
fi
