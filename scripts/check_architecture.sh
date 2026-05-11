#!/usr/bin/env bash
set -euo pipefail

failures=0

check_forbidden_imports() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if rg -n "^import (${pattern})$" "$path" >/tmp/alertcalendar-architecture-check.txt; then
    echo "Architecture rule failed: ${label}" >&2
    cat /tmp/alertcalendar-architecture-check.txt >&2
    failures=$((failures + 1))
  fi
}

check_forbidden_imports "Sources/AlertCalendar/Core/Settings" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Settings must stay platform-UI free"
check_forbidden_imports "Sources/AlertCalendar/Features/Football/Core" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Football/Core must stay UI and platform integration free"
check_forbidden_imports "Sources/AlertCalendar/Core/Slack" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Slack must stay UI and calendar integration free"

if (( failures > 0 )); then
  exit 1
fi

echo "Architecture checks passed."
