#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AlertCalendar"
BINARY_NAME="AlertCalendar"
BUNDLE_IDENTIFIER="com.zworehl.alertcalendar"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
APP_BUILD="${APP_BUILD:-$(tr -d '[:space:]' < "$ROOT/BUILD_NUMBER")}"
APP_DIR="${APP_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-1}"
REMOVE_DUPLICATE_INSTALLS="${REMOVE_DUPLICATE_INSTALLS:-1}"
TERMINATE_RUNNING_INSTANCES="${TERMINATE_RUNNING_INSTANCES:-1}"
ICON_SOURCE="$ROOT/Sources/AlertCalendar/Resources/Images/icon.png"
ENTITLEMENTS_PATH="$ROOT/AlertCalendar.entitlements"
USER_APP_DIR="$HOME/Applications"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
DEPLOYMENT_TARGET="13.0"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/install-derived-data}"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$BUILD_CONFIGURATION"
INTERMEDIATES_DIR="$DERIVED_DATA/Build/Intermediates.noindex/AlertCalendar.build/$BUILD_CONFIGURATION/AlertCalendar.build"
OBJECTS_DIR="$INTERMEDIATES_DIR/Objects-normal/$BUILD_ARCH"
SOURCE_FILE_LIST="$OBJECTS_DIR/${BINARY_NAME}.SwiftFileList"
SWIFT_CONST_VALS_LIST="$DERIVED_DATA/${BINARY_NAME}.swiftconstvalues.list"
FOCUS_METADATA_DIR="$DERIVED_DATA/FocusMetadata"
TARGET_TRIPLE="${BUILD_ARCH}-apple-macos${DEPLOYMENT_TARGET}"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${BINARY_NAME}.bundle"
RESOURCE_BUNDLE_SOURCE="$PRODUCTS_DIR/$RESOURCE_BUNDLE_NAME"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
CODE_SIGN_TIMESTAMP="${CODE_SIGN_TIMESTAMP:-auto}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://zworehl.github.io/AlertCalendar/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-v/PoTWPi7kSadVs/EaI7OieVS+pufgkiCmm/jSW+ioA=}"

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

check_duplicate_source_copies() {
  "$ROOT/scripts/check_duplicate_sources.sh"
}

resolve_code_sign_identity() {
  if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    printf '%s\n' "-"
    return
  fi

  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | awk 'match($0, /"Apple Development:[^"]+"/) && !found {
        print substr($0, RSTART + 1, RLENGTH - 2)
        found = 1
      }'
}

running_app_pids() {
  pgrep -x "$BINARY_NAME" 2>/dev/null || true
}

terminate_running_instances() {
  local pid
  local pids=()
  local remaining=()
  local deadline

  while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
      pids+=("$pid")
    fi
  done < <(running_app_pids)

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return
  fi

  echo "Stopping running ${APP_NAME} instance(s): ${pids[*]}"
  osascript -e "tell application id \"$BUNDLE_IDENTIFIER\" to quit" >/dev/null 2>&1 || true

  deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    remaining=()
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        remaining+=("$pid")
      fi
    done

    if [[ "${#remaining[@]}" -eq 0 ]]; then
      return
    fi

    sleep 0.2
  done

  for pid in "${remaining[@]}"; do
    echo "Force stopping stale ${APP_NAME} instance: $pid"
    kill "$pid" 2>/dev/null || true
  done

  sleep 1
  for pid in "${remaining[@]}"; do
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  done
}

generate_app_intents_metadata() {
  local metadata_tool
  local developer_dir
  local sdk_root
  local xcode_build_version
  local output_path

  metadata_tool="$(xcrun --find appintentsmetadataprocessor)"
  developer_dir="$(xcode-select -p)"
  sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
  xcode_build_version="$(xcodebuild -version | awk '/Build version/ { print $3 }')"
  output_path="$FOCUS_METADATA_DIR"
  mkdir -p "$output_path"

  if [[ ! -f "$SOURCE_FILE_LIST" ]]; then
    # SwiftPM product targets use the -p suffix with newer Xcode versions.
    OBJECTS_DIR="$DERIVED_DATA/Build/Intermediates.noindex/AlertCalendar.build/$BUILD_CONFIGURATION/AlertCalendar-p.build/Objects-normal/$BUILD_ARCH"
    SOURCE_FILE_LIST="$OBJECTS_DIR/${BINARY_NAME}.SwiftFileList"
  fi
  if [[ ! -f "$SOURCE_FILE_LIST" ]]; then
    echo "Unable to locate Swift source list for App Intents metadata."
    exit 1
  fi

  find "$OBJECTS_DIR" -name '*.swiftconstvalues' -print > "$SWIFT_CONST_VALS_LIST"
  if [[ ! -s "$SWIFT_CONST_VALS_LIST" ]]; then
    echo "Unable to locate Swift constant values for App Intents metadata."
    exit 1
  fi

  "$metadata_tool" \
    --output "$output_path" \
    --toolchain-dir "$developer_dir/Toolchains/XcodeDefault.xctoolchain" \
    --module-name "$BINARY_NAME" \
    --sdk-root "$sdk_root" \
    --xcode-version "$xcode_build_version" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT_TARGET" \
    --target-triple "$TARGET_TRIPLE" \
    --source-file-list "$SOURCE_FILE_LIST" \
    --swift-const-vals-list "$SWIFT_CONST_VALS_LIST" \
    --quiet-warnings \
    --force

  if [[ ! -f "$FOCUS_METADATA_DIR/Metadata.appintents/extract.actionsdata" ]]; then
    echo "App Intents metadata was not generated correctly."
    exit 1
  fi
}

compile_asset_catalog() {
  local asset_tmp
  local asset_catalog

  asset_tmp="$(mktemp -d)"
  asset_catalog="$asset_tmp/Assets.xcassets"

  mkdir -p "$asset_catalog/AccentColor.colorset"
  cat > "$asset_catalog/Contents.json" <<'JSON'
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON
  cat > "$asset_catalog/AccentColor.colorset/Contents.json" <<'JSON'
{
  "colors": [
    {
      "idiom": "universal",
      "color": {
        "color-space": "srgb",
        "components": {
          "red": "0.250",
          "green": "0.560",
          "blue": "0.960",
          "alpha": "1.000"
        }
      }
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON

  if ! xcrun actool "$asset_catalog" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target "$DEPLOYMENT_TARGET" \
    --output-format human-readable-text >/dev/null; then
    rm -rf "$asset_tmp"
    echo "Unable to compile asset catalog."
    exit 1
  fi

  rm -rf "$asset_tmp"
}

remove_duplicate_installs() {
  local candidate

  for search_dir in "$USER_APP_DIR" /Applications; do
    [[ -d "$search_dir" ]] || continue
    while IFS= read -r candidate; do
      if [[ "$candidate" != "$APP_BUNDLE" ]]; then
        echo "Removing duplicate install: $candidate"
        rm -rf "$candidate"
      fi
    done < <(find "$search_dir" -maxdepth 2 -iname "${APP_NAME}.app" -print 2>/dev/null)
  done
}

check_duplicate_source_copies

CODE_SIGN_IDENTITY="$(resolve_code_sign_identity)"
if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  echo "A code-signing identity is required."
  echo "Set CODE_SIGN_IDENTITY to a valid identity, or '-' for an ad hoc public preview build."
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "Unable to locate signing entitlements: $ENTITLEMENTS_PATH"
  exit 1
fi

echo "[1/4] Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
if [[ "$CLEAN_BUILD" == "1" ]]; then
  rm -rf "$DERIVED_DATA"
fi
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

SPARKLE_FRAMEWORK_SOURCE="$(find "$PRODUCTS_DIR" -path '*/Sparkle.framework' -type d -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" || ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Unable to locate the Sparkle framework in build products."
  exit 1
fi

generate_app_intents_metadata

echo "[2/4] Installing to ${APP_BUNDLE}..."
if [[ "$TERMINATE_RUNNING_INSTANCES" == "1" ]]; then
  terminate_running_instances
fi
if [[ "$REMOVE_DUPLICATE_INSTALLS" == "1" ]]; then
  remove_duplicate_installs
fi
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
if ! otool -l "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}" \
  | grep -A2 LC_RPATH \
  | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BUNDLE/Contents/MacOS/${BINARY_NAME}"
fi
ditto "$RESOURCE_BUNDLE_SOURCE" "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE_NAME"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
ditto "$FOCUS_METADATA_DIR/Metadata.appintents" "$APP_BUNDLE/Contents/Resources/Metadata.appintents"
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
compile_asset_catalog

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string></array>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_IDENTIFIER}</string>
  <key>CFBundleExecutable</key>
  <string>${BINARY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSCalendarsUsageDescription</key>
  <string>AlertCalendar needs Calendar access to show events, apply your per-calendar alert rules, and manage selected holidays, football fixtures, and game-sale campaigns.</string>
  <key>NSRemindersUsageDescription</key>
  <string>AlertCalendar needs Reminders access to show your pending reminders.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>AlertCalendar needs full Calendar access to read events, apply your per-calendar alert rules, and manage selected holidays, football fixtures, and game-sale campaigns.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>AlertCalendar uses Apple Events to reveal selected managed events in Calendar, read matching Mail context when enabled, and read current playback from Apple Music or a supported YouTube Music browser when you enable Music status sync.</string>
  <key>NSAppDataUsageDescription</key>
  <string>AlertCalendar reads local browser profile names so calendar meeting links can open in the profile you choose.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>AlertCalendar needs full Reminders access to show reminder due dates and any available due times.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>AlertCalendar uses your location to calculate local sun events.</string>
  <key>NSLocationUsageDescription</key>
  <string>AlertCalendar uses your location to calculate local sun events.</string>
  <key>NSContactsUsageDescription</key>
  <string>AlertCalendar uses your contacts to show organizer photos and invitee names in meeting previews.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

echo "[3/4] Finalizing bundle..."
xattr -cr "$APP_BUNDLE" || true
echo "Signing with: $CODE_SIGN_IDENTITY"
TIMESTAMP_ARGUMENT="--timestamp=none"
if [[ "$CODE_SIGN_TIMESTAMP" == "1" || ( "$CODE_SIGN_TIMESTAMP" == "auto" && "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application:* ) ]]; then
  TIMESTAMP_ARGUMENT="--timestamp"
fi
SIGNING_OPTION_ARGUMENTS=()
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  SIGNING_OPTION_ARGUMENTS+=(--options runtime)
fi
codesign \
  --force \
  --deep \
  "${SIGNING_OPTION_ARGUMENTS[@]}" \
  "$TIMESTAMP_ARGUMENT" \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$CODE_SIGN_IDENTITY" \
  "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "[4/4] Done."
echo "Installed: $APP_BUNDLE"

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  open "$APP_BUNDLE" || true
fi
