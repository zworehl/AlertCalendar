# AlertCalendar

AlertCalendar is a macOS menu bar app that keeps Calendar events, Reminders, astronomy moments, and managed football fixtures visible in one continuously updating workflow.

It is built as a Swift Package, installs as a lightweight `.app` bundle, and uses Apple frameworks directly without third-party Swift package dependencies.

## Contents

- [What It Does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Run From Source](#run-from-source)
- [Settings](#settings)
- [Permissions](#permissions)
- [Data And Privacy](#data-and-privacy)
- [Project Layout](#project-layout)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Maintainer Notes](#maintainer-notes)

## What It Does

AlertCalendar combines time-sensitive information into a single menu bar surface:

- Upcoming Calendar events, active events, all-day events, and reminders.
- Optional astronomy feeds for sunrise, sunset, solar noon, solar midnight, moon phases, and orbital highlights.
- Optional managed football fixtures backed by ESPN data and written to Apple Calendar.
- Meeting-aware previews, join-link extraction, attendee context, and location previews when enough metadata is available.

The app is meant to make the menu bar behave like a live operational timeline instead of a passive clock or event count.

## Requirements

- macOS 13 or later.
- Swift 6.2 or later.
- Xcode Command Line Tools.

Install command line tools if needed:

```bash
xcode-select --install
```

## Install

Build and install the app bundle:

```bash
./install.sh
```

By default, this writes:

```text
/Applications/AlertCalendar.app
```

`install.sh` is intentionally explicit and local. It:

1. Builds with `xcodebuild` using the `AlertCalendar` scheme.
2. Uses `BUILD_CONFIGURATION` and `BUILD_ARCH` when provided.
3. Removes duplicate `AlertCalendar.app` installs in `/Applications` and `~/Applications`.
4. Recreates the target app bundle.
5. Copies the executable and SwiftPM resource bundle.
6. Generates `AppIcon.icns` from `Sources/AlertCalendar/Resources/Images/icon.png`.
7. Writes the app `Info.plist` usage descriptions.
8. Clears extended attributes.
9. Applies ad-hoc signing.
10. Opens the app unless `OPEN_AFTER_INSTALL=0`.

Install somewhere else:

```bash
APP_DIR="$HOME/Applications" ./install.sh
```

Install without opening:

```bash
OPEN_AFTER_INSTALL=0 ./install.sh
```

Use a specific architecture or configuration:

```bash
BUILD_ARCH=arm64 BUILD_CONFIGURATION=Release ./install.sh
```

Uninstall by removing the app bundle:

```bash
rm -rf /Applications/AlertCalendar.app
```

## Run From Source

Development run:

```bash
swift run
```

Development build:

```bash
swift build
```

Release bundle validation should use the installer because it writes the runtime `Info.plist`, resources, icon, and ad-hoc signature.

## Settings

AlertCalendar has four top-level settings tabs:

- `General`: menu bar behavior, alerts, countdowns, rotation, look-ahead windows, font size, and title truncation.
- `Feeds`: astronomy feeds and football fixture management.
- `Calendars & Reminders`: source inclusion, selected calendars, selected reminder lists, and weekday-only sets.
- `Permissions`: Calendar, Reminders, Location, and Contacts access cards with actions and System Settings shortcuts.

Astronomy supports automatic location or manual coordinates. When automatic location is enabled, the manual coordinate fields should stay hidden.

Football fixture management supports:

- A writable target calendar.
- One alert policy for managed football events.
- Supported competition browsing.
- Live and next-day match overview.
- Managed match review.
- Automatic updates for status, venue, timing context, and metadata.
- Automatic cleanup when fixtures fall outside the suggestion window.

Focus Filters were intentionally removed from the app. Do not reintroduce Focus Filter UI, App Intents metadata, or stored focus calendar overrides.

## Permissions

AlertCalendar may request these macOS permissions:

- `Calendar`: read events, build the event queue, add/update managed football fixtures, and reveal selected fixtures in Calendar.
- `Reminders`: read reminders with due times and include them in the menu workflow.
- `Location`: detect astronomy coordinates automatically.
- `Contacts`: resolve meeting organizer and attendee names/photos.
- `Apple Events`: open selected managed football fixtures in Apple Calendar when requested.

If Location is denied, astronomy can still use manual coordinates.

## Data And Privacy

Most app behavior is local and uses Apple frameworks:

- `SwiftUI`, `AppKit`, `Foundation`
- `EventKit`
- `Contacts`
- `CoreLocation`
- `MapKit`

Network access is limited to feature-specific flows:

- ESPN endpoints under `site.api.espn.com` and `sports.core.api.espn.com` for football fixtures, summaries, teams, venues, statistics, and logos.
- Slack API calls when Slack status sync is configured.
- `https://ipapi.co/json/` as an approximate location fallback when macOS Location permission is granted but Core Location does not return coordinates.
- Apple-backed geocoding/search via `CLGeocoder` and `MKLocalSearch` for map previews and structured football locations.

Local storage includes:

- User settings in `UserDefaults`.
- Slack connection data and tokens through the app's Slack/Keychain flow.
- Managed football event records.
- Cached football imagery in Application Support.

The UI should not display raw automatic coordinates redundantly. Coordinates are implementation data, not primary user-facing content.

## Project Layout

```text
Sources/AlertCalendar/
├── App/
├── Core/
│   ├── Astronomy/
│   ├── Location/
│   ├── Meetings/
│   ├── Monitor/
│   ├── Settings/
│   ├── Slack/
│   └── System/
├── Features/
│   └── Football/
├── Resources/
├── Shared/
└── UI/
    ├── Menu/
    └── Settings/
```

Important root files:

- `Package.swift`: Swift Package definition.
- `install.sh`: local release bundle builder/installer.
- `scripts/verify.sh`: local CI-style validation.
- `Tests/AlertCalendarTests/`: unit and behavior tests.
- `coverage-gate.conf` and `scripts/check_coverage.sh`: local coverage gate.

## Development

Recommended local loop:

```bash
swift test
./install.sh
```

Run the full local verification path:

```bash
./scripts/verify.sh
```

Run the coverage gate:

```bash
./scripts/check_coverage.sh
```

The package currently defines one executable target, `AlertCalendar`, and one test target, `AlertCalendarTests`.

Keep source files below 500 lines. If a file approaches that limit, split by domain, UI subsection, parsing concern, or coordinator responsibility before adding more behavior.

## Troubleshooting

If the app builds but does not appear in the menu bar:

- Confirm the app is running.
- Launch `/Applications/AlertCalendar.app` manually once.
- Reinstall with `./install.sh` to refresh the bundle and ad-hoc signature.

If macOS does not prompt for a denied permission again:

- Open the app's Permissions tab.
- Use the relevant Open Settings action.
- Grant access directly in System Settings.

If astronomy is empty:

- Confirm astronomy feeds are enabled.
- Confirm at least one astronomy category is visible.
- If automatic location is off, enter valid manual coordinates.
- If automatic location is on, confirm Location permission is granted.

If football fixtures do not appear:

- Use the Feeds tab, not the standard Calendar source list.
- Confirm Calendar access is granted.
- Confirm a writable target calendar is selected.
- Confirm the desired competition is supported and inside the suggestion window.

If meeting names, avatars, or maps are sparse:

- Grant Contacts for richer meeting names/photos.
- Some events do not include enough location metadata for map context.
- Virtual meetings intentionally avoid physical-location treatment.

## Maintainer Notes

- `CalendarMonitor` is currently the central orchestration pipeline. Prefer extracting new behavior into focused services or coordinators instead of growing it further.
- Settings normalization belongs in `AppSettingsRules` and `AppSettingsStore`, not duplicated in views.
- Football parsing should remain defensive because external feed structures are inconsistent.
- Installer behavior and README install docs should stay in sync.
- Validate behavior changes with `swift test` and `./install.sh`.
