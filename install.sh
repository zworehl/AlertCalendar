#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AlertCalendar"
BINARY_NAME="AlertCalendar"
APP_DIR="${APP_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-1}"
ICON_SOURCE="$ROOT/Sources/AlertCalendar/Resources/Images/icon.png"
USER_APP_DIR="$HOME/Applications"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
DEPLOYMENT_TARGET="13.0"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/install-derived-data}"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$BUILD_CONFIGURATION"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${BINARY_NAME}.bundle"
RESOURCE_BUNDLE_SOURCE="$PRODUCTS_DIR/$RESOURCE_BUNDLE_NAME"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer supports macOS only."
  exit 1
fi

case "$BUILD_ARCH" in
  arm64|x86_64)
    ;;
  *)
    echo "Unsupported macOS architecture: $BUILD_ARCH"
    exit 1
    ;;
esac

BINARY_PATH="$PRODUCTS_DIR/$BINARY_NAME"

APP_BUNDLE="$APP_DIR/${APP_NAME}.app"

remove_duplicate_installs() {
  local candidate

  while IFS= read -r candidate; do
    if [[ "$candidate" != "$APP_BUNDLE" ]]; then
      echo "Removing duplicate install: $candidate"
      rm -rf "$candidate"
    fi
  done < <(find "$USER_APP_DIR" /Applications -maxdepth 2 -iname "${APP_NAME}.app" -print 2>/dev/null)
}

echo "[1/4] Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
rm -rf "$DERIVED_DATA"
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration "$BUILD_CONFIGURATION" \
  -destination "platform=macOS,arch=$BUILD_ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Unable to locate built binary: ${BINARY_NAME}"
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_SOURCE" ]]; then
  echo "Unable to locate SwiftPM resource bundle: ${RESOURCE_BUNDLE_NAME}"
  exit 1
fi

echo "[2/4] Installing to ${APP_BUNDLE}..."
remove_duplicate_installs
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
ditto "$RESOURCE_BUNDLE_SOURCE" "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE_NAME"
if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSCalendarsUsageDescription</key>
  <string>AlertCalendar needs Calendar access to show upcoming events and alerts.</string>
  <key>NSRemindersUsageDescription</key>
  <string>AlertCalendar needs Reminders access to show your pending reminders.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>AlertCalendar needs full Calendar access to read upcoming events and trigger alerts.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>AlertCalendar uses Apple Events to open selected fixtures directly in Calendar when you ask it to.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>AlertCalendar needs full Reminders access to show reminder due times.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>AlertCalendar uses your location to calculate local sun events.</string>
  <key>NSLocationUsageDescription</key>
  <string>AlertCalendar uses your location to calculate local sun events.</string>
  <key>NSContactsUsageDescription</key>
  <string>AlertCalendar uses your contacts to show organizer photos and invitee names in meeting previews.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "[3/4] Finalizing bundle..."
xattr -cr "$APP_BUNDLE" || true
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "[4/4] Done."
echo "Installed: $APP_BUNDLE"

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  open "$APP_BUNDLE" || true
fi
