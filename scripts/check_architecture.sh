#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_TMP_DIR="$(mktemp -d)"
failures=0

trap 'rm -rf "$CHECK_TMP_DIR"' EXIT

cd "$ROOT_DIR"

./scripts/check_duplicate_sources.sh

check_forbidden_imports() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  local output_path="$CHECK_TMP_DIR/forbidden-imports.txt"

  if rg -n "^import (${pattern})$" "$path" >"$output_path"; then
    echo "Architecture rule failed: ${label}" >&2
    cat "$output_path" >&2
    failures=$((failures + 1))
  fi
}

check_forbidden_usage_outside() {
  local path="$1"
  local pattern="$2"
  local allowed_path="$3"
  local label="$4"

  local output_path="$CHECK_TMP_DIR/forbidden-usage.txt"

  if rg -n "$pattern" "$path" \
    | rg -v -F "${allowed_path}:" >"$output_path"; then
    echo "Architecture rule failed: ${label}" >&2
    cat "$output_path" >&2
    failures=$((failures + 1))
  fi
}

check_file_length() {
  local path="$1"
  local maximum_lines="$2"
  local label="$3"
  local output_path="$CHECK_TMP_DIR/file-length-${maximum_lines}.txt"

  rg --files "$path" -g '*.swift' -0 \
    | xargs -0 wc -l \
    | awk -v maximum="$maximum_lines" '$2 != "total" && $1 > maximum { print }' \
    >"$output_path"

  if [[ -s "$output_path" ]]; then
    echo "Architecture rule failed: ${label}" >&2
    cat "$output_path" >&2
    failures=$((failures + 1))
  fi
}

check_forbidden_imports "Sources/AlertCalendar/Core/Settings" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Settings must stay platform-UI free"
check_forbidden_imports "Sources/AlertCalendar/Core/Meetings/MeetingBrowserRouting.swift" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "MeetingBrowserRouting must stay platform-UI free"
check_forbidden_imports "Sources/AlertCalendar/Core/Monitor/Base/CalendarMonitor.swift" "CoreLocation|CoreWLAN" "CalendarMonitor base should keep feature runtime state in dedicated state files"
check_forbidden_imports "Sources/AlertCalendar/Features/Football/Core" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Football/Core must stay UI and platform integration free"
check_forbidden_imports "Sources/AlertCalendar/Features/GameSales/Core" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "GameSales/Core must stay UI and platform integration free"
check_forbidden_imports "Sources/AlertCalendar/Core/Slack" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Slack must stay UI and calendar integration free"
check_forbidden_imports "Sources/AlertCalendar/Shared" "AppKit|SwiftUI|EventKit|CoreLocation|CoreWLAN|MapKit|Contacts" "Shared must stay platform free"
check_forbidden_imports "Sources/AlertCalendar/UI/Settings/State" "AppKit|SwiftUI|EventKit|CoreLocation|CoreWLAN|MapKit|Contacts" "Settings/State must stay platform and UI free"

check_forbidden_usage_outside "Sources/AlertCalendar" "NSWorkspace\\.shared" "Sources/AlertCalendar/Core/System/AlertCalendarWorkspace.swift" "NSWorkspace.shared must stay behind AlertCalendarWorkspace"
check_forbidden_usage_outside "Sources/AlertCalendar" "NSSound\\.beep\\(" "Sources/AlertCalendar/Core/System/AlertCalendarSoundPlayer.swift" "NSSound.beep must stay behind AlertCalendarSoundPlayer"
check_forbidden_usage_outside "Sources/AlertCalendar" "Process\\(\\)" "Sources/AlertCalendar/Core/System/AlertCalendarProcessRunner.swift" "Process construction must stay behind AlertCalendarProcessRunner"
check_forbidden_usage_outside "Sources/AlertCalendar" "URLSession\\.shared" "Sources/AlertCalendar/Core/System/AlertCalendarHTTPClient.swift" "URLSession.shared must stay behind an HTTP adapter"
check_forbidden_usage_outside "Sources/AlertCalendar/UI/Settings" "title: \"Add To\"|Text\\(\"Add To\"\\)" "Sources/AlertCalendar/UI/Settings/Shared/SettingsLabeledControls.swift" "Settings Add To controls must use SettingsAddToCalendarPicker"
check_forbidden_usage_outside "Sources/AlertCalendar/UI/Settings" "SettingsControlLabel\\(" "Sources/AlertCalendar/UI/Settings/Shared/SettingsLabeledControls.swift" "Settings labels must be composed through shared labeled controls"

check_file_length "Sources/AlertCalendar" 500 "source files must stay at or below 500 lines"
check_file_length "Tests/AlertCalendarTests" 1000 "test files must stay at or below 1,000 lines"

if (( failures > 0 )); then
  exit 1
fi

echo "Architecture checks passed."
