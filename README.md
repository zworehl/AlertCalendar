# AlertCalendar

AlertCalendar is a macOS menu bar app that keeps Calendar events, Reminders, astronomy moments, and managed football fixtures visible in one continuously updating menu bar workflow.

It is built as a pure Swift Package, ships as a lightweight menu bar utility, and uses Apple system frameworks directly instead of adding third-party package dependencies.

## Table of Contents

- [What the App Does](#what-the-app-does)
- [Current Feature Set](#current-feature-set)
- [Requirements](#requirements)
- [Installation](#installation)
- [Running from Source](#running-from-source)
- [Settings Walkthrough](#settings-walkthrough)
- [Permissions](#permissions)
- [Data Sources and Integrations](#data-sources-and-integrations)
- [Project Layout](#project-layout)
- [Development Workflow](#development-workflow)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)
- [Privacy Notes](#privacy-notes)

## What the App Does

AlertCalendar combines several kinds of time-sensitive information into a single menu bar experience:

- Upcoming Calendar events
- Active events already in progress
- All-day events
- Reminders with due times
- Optional astronomy feeds such as sunrise, sunset, moon phases, and orbital highlights
- Optional football fixtures that AlertCalendar can add to Apple Calendar and maintain automatically

The app is designed for people who want the menu bar to act as a live operational timeline rather than a passive clock or a simple event count.

## Current Feature Set

### Menu Bar Behavior

- Renders a compact, continuously refreshed menu bar label.
- Supports rotating through concurrent items instead of dropping everything after the first item.
- Highlights items that enter the alert window with a blinking red treatment when enabled.
- Supports configurable rotation windows, dropdown look-ahead windows, title truncation, font sizing, and countdown style.
- Shows active events as elapsed time or remaining time, depending on user preference.

### Dropdown Content

- Lists timed events, active events, reminders, and all-day items.
- Preserves calendar colors and marker styles.
- Uses contextual previews for selected items when relevant.
- Includes meeting-aware actions and richer previews when enough metadata is available.

### Meeting and Contextual Enhancements

- Extracts meeting links from event URLs, notes, and locations.
- Recognizes common meeting providers and prefers real join links over generic landing pages.
- Resolves organizer and attendee names and thumbnails from Contacts when permission is granted.
- Shows location-aware context for events when geographic data is available.

### Astronomy Feeds

- Supports local sunrise and sunset.
- Supports solar noon and solar midnight.
- Supports estimated moon phase change moments.
- Supports orbital highlights such as perihelion, aphelion, equinoxes, and solstices.
- Includes a detailed astronomy preview UI with a daylight world map, moon phase cards, and orbital artwork.
- Can use automatic system location or manually entered coordinates.

### Football Fixture Management

- Loads curated football competitions from ESPN-backed feeds.
- Shows football fixtures inside the Feeds settings workflow.
- Supports adding managed fixtures to a writable Apple Calendar.
- Applies a single configured Apple Calendar alert policy to all managed fixtures.
- Refreshes fixture details, status, venue, and supporting metadata over time.
- Removes managed fixtures automatically when they fall outside the configured suggestion window.
- Caches football metadata such as logos locally.

### Settings Window

- Opens as a full windowed settings experience rather than a tiny popover.
- Supports full screen for the settings window.
- Splits settings across General, Feeds, Calendars & Reminders, and Permissions tabs.
- Includes an overview of current access state and last refresh timing.
- Provides direct actions to retry permission-dependent flows or open privacy settings.

## Requirements

- macOS 13 or later
- Swift 6.2 or later
- Xcode Command Line Tools

Install command line tools if needed:

```bash
xcode-select --install
```

## Installation

### Quick Install

Build and install the app bundle with:

```bash
./install.sh
```

By default, the installer writes the app bundle to:

```text
/Applications/AlertCalendar.app
```

Detailed installer notes are also available in [INSTALL.md](INSTALL.md).

### What `install.sh` Actually Does

The installer is intentionally explicit and local:

1. Builds the package in `release` mode with `swift build -c release`.
2. Locates the compiled `AlertCalendar` executable in `.build`.
3. Removes duplicate `AlertCalendar.app` installs it finds in `/Applications` and `~/Applications`.
4. Recreates the target `.app` bundle from scratch.
5. Generates an `.icns` bundle from `Sources/AlertCalendar/Resources/Images/icon.png`.
6. Writes the app `Info.plist` with the required usage descriptions.
7. Clears extended attributes from the bundle.
8. Applies ad-hoc signing with `codesign --sign -`.
9. Opens the app automatically unless disabled.

### Installer Options

Install to a custom directory:

```bash
APP_DIR="$HOME/Applications" ./install.sh
```

Install without auto-opening the app:

```bash
OPEN_AFTER_INSTALL=0 ./install.sh
```

### Uninstall

If you installed using the local script, uninstalling is simply removing the app bundle:

```bash
rm -rf /Applications/AlertCalendar.app
```

If you installed elsewhere, remove that copy instead.

## Running from Source

Launch directly from the Swift Package in development mode:

```bash
swift run
```

This is useful when you want fast iteration without rebuilding a release bundle.

## Settings Walkthrough

AlertCalendar has four top-level settings tabs and one secondary split inside Feeds.

### General

The General tab controls menu bar behavior and alert presentation.

Key options include:

- Red blinking alert enable/disable
- Alert lead time in minutes
- Queue rotation interval in seconds
- Menu bar rotation window
- Dropdown look-ahead window
- Contextual preview lead time
- Maximum number of visible dropdown items
- Menu bar font size
- Ellipsis behavior for long titles
- Maximum title length when ellipsis is enabled
- Simplified countdown formatting
- Active event timer mode: elapsed or remaining

### Feeds

The Feeds tab manages non-calendar data sources.

It is split into two subsections:

- Astronomy
- Football Fixtures

#### Astronomy Feeds

The astronomy subsection includes:

- A master toggle for all atmosphere moments
- Per-category toggles for:
  - Sunrise & Sunset
  - Solar Noon & Midnight
  - Moon Phases
  - Orbital Highlights
- A full preview area that shows:
  - Daylight world map
  - Calculated solar times
  - Upcoming lunar phases
  - Upcoming orbital highlights

The astronomy preview reflects the currently selected coordinates and current time zone.

#### Football Fixtures

The football subsection allows AlertCalendar to manage supported football fixtures as Apple Calendar events.

You can:

- Pick the destination calendar used for managed fixtures
- Choose one alert policy for all managed football events
- Browse supported competitions
- View a live-and-next-day overview
- Review already added managed matches
- Tune how far back finished matches remain visible
- Tune how far ahead upcoming matches remain visible

Important behavior:

- AlertCalendar only manages fixtures inside its supported suggestion window.
- If a managed fixture ages out of that window, the app removes it from Apple Calendar automatically.
- Football support is optional and can be ignored entirely if you only care about Calendar, Reminders, and astronomy.

### Calendars & Reminders

This tab controls which Apple data sources are visible by default.

It includes:

- Global source toggles:
  - Include Calendar Events
  - Include All-day Events
  - Include Reminders
- Default selection management for:
  - Event calendars
  - Reminder calendars
  - Weekday-only calendar sets for each side

This is where you scope the app to only the calendars and reminders you actually want in the menu bar workflow.

### Permissions

This tab centralizes access management for all privacy-sensitive integrations.

It includes:

- A current access summary
- A last refresh timestamp
- Per-permission action cards
- Shortcuts into relevant System Settings privacy pages
- Automatic versus manual astronomy location control
- Manual latitude and longitude entry
- A detect-now action for current coordinates

The app defines dedicated workflows for:

- Calendar events
- Reminders
- Location
- Contacts

## Permissions

Depending on which features you use, AlertCalendar may request access to some or all of the following:

### Calendar

Used to:

- Read event metadata
- Build the event queue
- Detect active and upcoming items
- Add and update managed football fixtures
- Reveal selected fixtures directly in Apple Calendar

### Reminders

Used to:

- Read reminders with due times
- Include reminders in the dropdown and menu rotation

### Location

Used to:

- Detect current coordinates automatically for astronomy feeds
- Improve location-aware previews when geographic context is available

Manual coordinates are supported if you prefer not to grant Location access.

### Contacts

Used to:

- Resolve attendee and organizer names
- Show thumbnails in meeting previews

If Contacts access is denied, the meeting flows still work, but they fall back to the event-provided names or email addresses.

### Apple Events

Used to:

- Open managed football fixtures directly in Apple Calendar when you request it

## Data Sources and Integrations

AlertCalendar uses a mix of local system APIs and optional network-backed football data.

### Apple System Frameworks

The project is built primarily on:

- `SwiftUI`
- `AppKit`
- `EventKit`
- `Contacts`
- `CoreLocation`
- `MapKit`
- `Foundation`

### Local Apple Data

The app reads local data through Apple frameworks for:

- Calendar events
- Reminders
- Contacts
- Manual or automatic location data

### Football Data

Football support uses ESPN-backed soccer endpoints, including summary and scoreboard-style feeds under:

- `site.api.espn.com`
- `sports.core.api.espn.com`

This feed layer powers:

- Competition browsing
- Match status updates
- Venue details
- Team details
- Goal scorers
- Match statistics
- Team and competition logos

### Geocoding and Maps

Location previews and structured football locations use:

- `MKLocalSearch`
- `CLGeocoder`

These are used to improve map previews and structured locations rather than to replace original event text.

## Project Layout

The repository is intentionally compact and organized by app surface and domain.

### Root Files

- `Package.swift`: Swift Package definition
- `README.md`: repository overview and usage guide
- `INSTALL.md`: short install reference
- `install.sh`: release build and local app bundle installer
- `coverage-gate.conf`: configuration for the coverage script
- `scripts/check_coverage.sh`: coverage gate helper

### Source Tree

```text
Sources/AlertCalendar/
├── App/
├── Core/
│   ├── Astronomy/
│   ├── Location/
│   ├── Meetings/
│   ├── Monitor/
│   └── Settings/
├── Features/
│   └── Football/
├── Resources/
│   └── Images/
├── Shared/
└── UI/
    ├── Menu/
    └── Settings/
```

### Directory Responsibilities

- `App/`
  - App entry point
  - App delegate
  - Window and application policy handling
- `Core/`
  - Shared logic for astronomy, meetings, settings, refresh cycles, location, and menu bar state
- `Core/Monitor/`
  - The main orchestration layer that gathers data, computes UI state, and drives updates
- `Features/Football/`
  - Football-specific models, API clients, formatters, and UI components
- `Resources/Images/`
  - App artwork and astronomy imagery
- `Shared/`
  - Shared models and styling utilities
- `UI/Menu/`
  - Menu bar label rendering, dropdown layout, and contextual content
- `UI/Settings/`
  - Settings tabs, controls, previews, and football management panels

### Tests

Tests live in:

```text
Tests/AlertCalendarTests/
```

The test suite covers:

- Settings rules and formatting
- Astronomy calculations and previews
- Calendar and all-day item handling
- Football parsing and formatting
- Meeting URL resolution
- Menu bar queue and rotation behavior
- Permissions and app window behavior

## Development Workflow

### Build

Development build:

```bash
swift build
```

Release build:

```bash
swift build -c release
```

### Run

```bash
swift run
```

### Reinstall Locally

```bash
./install.sh
```

### Useful Local Cycle

```bash
swift test
./install.sh
```

This is the safest loop when you are changing behavior that affects live menu bar state or installer output.

## Testing and Validation

### Run the Full Test Suite

```bash
swift test
```

### Run the Coverage Gate Script

```bash
./scripts/check_coverage.sh
```

The repository includes a coverage gate configuration and helper script for local validation.

### Package Shape

The package currently defines:

- One executable target: `AlertCalendar`
- One test target: `AlertCalendarTests`

There are no third-party Swift package dependencies in `Package.swift`.

## Troubleshooting

### The app builds but does not appear in the menu bar

- Make sure the app is actually running.
- If you installed with `./install.sh`, launch `/Applications/AlertCalendar.app` manually once.
- Reinstall with `./install.sh` to rebuild the bundle and refresh ad-hoc signing.

### Permissions were denied and the app is not prompting again

- Open the Permissions tab in the app.
- Use the per-permission actions and privacy shortcuts.
- If macOS no longer considers the app eligible for a native re-prompt, grant access directly in System Settings.

### Astronomy preview is empty

- Confirm astronomy feeds are enabled.
- Confirm at least one astronomy category is visible.
- If automatic location is off, enter valid manual coordinates.
- If automatic location is on, verify Location permission is granted.

### Football fixtures are not appearing

- Football is managed from the Feeds tab, not the standard Calendar source list.
- Make sure Calendar access is granted.
- Make sure a writable target calendar is selected.
- Remember that football fixtures are limited to the curated supported competition set and the suggestion window.

### Meeting names or avatars are missing

- Grant Contacts access if you want contact enrichment.
- Without Contacts permission, AlertCalendar falls back to event-provided names and email addresses.

### Location previews seem sparse or missing

- Some events do not contain enough structured location information to resolve map context.
- Virtual meetings intentionally avoid being treated as physical travel locations.

## Privacy Notes

AlertCalendar mixes local processing with optional network-backed football data.

### Processed Locally

These features are handled on-device via Apple frameworks:

- Calendar event loading
- Reminder loading
- Contacts matching
- Astronomy calculations
- Manual coordinate handling
- Most menu bar state and formatting logic

### Network Usage

Network access is mainly used for football support:

- Loading competition and fixture data
- Loading match summaries and statistics
- Resolving team details and logos

If you do not use football feeds, the app remains mostly a local Apple-frameworks utility.

### Cached Local Data

The app stores local settings and may cache downloaded football imagery in Application Support.

## Notes for Maintainers

- The menu bar experience is driven by a central `CalendarMonitor` state pipeline.
- Settings rules should stay centralized so UI controls and persisted values do not drift apart.
- Football parsing is intentionally defensive because it normalizes inconsistent external feed data.
- Astronomy preview code should stay visually clear but mathematically grounded, since it doubles as a confidence surface for the underlying calculations.

If you are updating behavior, prefer validating with:

```bash
swift test
./install.sh
```
