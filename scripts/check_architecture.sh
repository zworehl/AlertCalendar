#!/usr/bin/env bash
set -euo pipefail

failures=0

check_forbidden_imports() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if grep -R -n -E "^import (${pattern})$" "$path" >/tmp/alertcalendar-architecture-check.txt; then
    echo "Architecture rule failed: ${label}" >&2
    cat /tmp/alertcalendar-architecture-check.txt >&2
    failures=$((failures + 1))
  fi
}

check_forbidden_imports "Sources/AlertCalendar/Core/Settings" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Settings must stay platform-UI free"
check_forbidden_imports "Sources/AlertCalendar/Core/Meetings/MeetingBrowserRouting.swift" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "MeetingBrowserRouting must stay platform-UI free"
check_forbidden_imports "Sources/AlertCalendar/Core/Monitor/Base/CalendarMonitor.swift" "CoreLocation|CoreWLAN" "CalendarMonitor base should keep feature runtime state in dedicated state files"
check_forbidden_imports "Sources/AlertCalendar/Features/Football/Core" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Football/Core must stay UI and platform integration free"
check_forbidden_imports "Sources/AlertCalendar/Core/Slack" "AppKit|SwiftUI|EventKit|CoreLocation|MapKit|Contacts" "Core/Slack must stay UI and calendar integration free"
check_forbidden_imports "Sources/AlertCalendar/Shared" "AppKit|SwiftUI|EventKit|CoreLocation|CoreWLAN|MapKit|Contacts" "Shared must stay platform free"

if find Sources/AlertCalendar -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$2 != "total" && $1 > 500 { print }' \
  | tee /tmp/alertcalendar-file-length-check.txt \
  | grep . >/dev/null; then
  echo "Architecture rule failed: source files must stay at or below 500 lines" >&2
  cat /tmp/alertcalendar-file-length-check.txt >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

echo "Architecture checks passed."
