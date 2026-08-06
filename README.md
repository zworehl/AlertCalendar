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

AlertCalendar combines time-sensitive information into a menu bar workflow, with supporting feed management in Settings:

- Upcoming Calendar events, active events, all-day events, and reminders.
- Optional astronomy feeds for sunrise, sunset, solar noon, solar midnight, moon phases, and orbital highlights.
- Google holiday feeds for 256 countries and territories, consolidated into one writable Apple Calendar with country flags and semantic deduplication.
- Optional managed football fixtures backed by ESPN data and written to Apple Calendar.
- Scheduled game-sale campaigns from official Steam, Xbox, PlayStation, and Nintendo sources, shown as store-aware cards and optionally synchronized into Apple Calendar.
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
9. Signs with an Apple Development identity so permissions remain associated with a stable signature.
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

Use a specific signing identity:

```bash
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./install.sh
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

AlertCalendar has five top-level settings tabs:

Configuration controls are staged in the window until you choose `Apply`. The fixed action bar shows whether changes are pending, lets you revert the draft, and protects unapplied changes when you close Settings or quit the app. One-shot actions such as refreshing, requesting permissions, connecting an integration, or adding and removing managed calendar items still run immediately.

- `General`: menu bar behavior, alerts, countdowns, rotation, look-ahead windows, font size, and title truncation.
- `Feeds`: astronomy, Google holiday consolidation, football fixture management, and scheduled game-sale campaigns.
- `Calendars`: source inclusion, selected calendars, per-calendar event alert rules, selected reminder lists, and weekday-only sets.
- `Integrations`: connected services such as Slack status sync.
- `Access`: Calendar, Reminders, Location, and Contacts access cards with actions and System Settings shortcuts.

Astronomy supports automatic location or manual coordinates. When automatic location is enabled, the manual coordinate fields should stay hidden. Automatic coordinates refresh hourly, immediately after a Wi-Fi network change, and no more than once every 15 minutes when the app becomes active.

Slack status sync schedules meeting start, pre-event, rotation, and end transitions at their exact boundaries. A one-minute EventKit evaluation remains as a fallback while rules or managed statuses are active.

Each writable event calendar can define its own alert series for timed and all-day events. Rules can target every event or invitations only, preserve existing alerts or replace them exactly, and use Apple-style presets, custom relative times, and Calendar-provided Time to Leave metadata. Alerts are stored on the event and delivered by Apple Calendar using its normal notification settings. A background full sync covers historical and future events in four-year EventKit query blocks, while routine refreshes keep upcoming events current. AlertCalendar adds no app-specific alert-count limit; EventKit and the calendar provider decide what is accepted.

Football fixture management supports:

- A writable target calendar.
- One alert policy for managed football events.
- Supported competition browsing.
- Live and next-day match overview.
- Managed match review.
- Automatic updates for status, venue, timing context, and metadata.
- Adaptive polling: every 30 seconds while live, every minute around kickoff or during the first 10 minutes after a known final, every 5 minutes while approaching or recovering a delayed result, every 15 minutes for the next 24 hours, and every 3 hours for distant fixtures. Settled finished matches stop polling until a manual or event-driven refresh.
- Contextual ESPN scoreboard caching: five minutes for ranges containing today and one hour for distant ranges; per-match summaries retain their 15-second cache.
- Automatic cleanup when fixtures fall outside the suggestion window.

Google Holidays supports:

- The complete set of 256 countries and territories with a verified public Google Calendar holiday feed.
- Detection of country calendars already subscribed in Apple Calendar.
- One writable destination calendar for every selected country feed.
- All-day event titles prefixed with country flags.
- One event per normalized holiday name and date, combining every matching country flag when several feeds contain the same holiday.
- A fixed weekly refresh, with an immediate check after changing the selected countries or using Refresh now.
- Managed cleanup when countries are deselected or Google removes an event from its feed.

Game Sales supports:

- A writable target Apple Calendar, preferring an existing calendar named `Game Sales`.
- All-day campaign cards with start/end dates, official links, and add/open/remove actions.
- Independent, opt-in automatic addition for Steam, Xbox, PlayStation, and Nintendo Switch; every store is off by default.
- Store-aware detection for Steam, Xbox, PlayStation Store, and Nintendo eShop events already present in the selected calendar.
- One Apple Calendar alert policy, defaulting to 15 minutes before the campaign begins.
- Optional notifications when AlertCalendar automatically adds a newly announced campaign.
- Automatic removal of ended sale events from the dedicated target calendar and semantic duplicate prevention.
- A six-hour cache for successful source documents, evaluated every 15 minutes so failed sources can retry with exponential backoff. Refresh now bypasses the cache for an immediate check.

Steam publishes a structured future campaign schedule. Xbox, PlayStation, and Nintendo do not publish an equivalent complete calendar, so AlertCalendar also checks their official announcement feeds and only imports a console campaign when the announcement states both its start and end. Console coverage is therefore opportunistic and may be incomplete; AlertCalendar never invents missing dates.

Focus Filters were intentionally removed from the app. Do not reintroduce Focus Filter UI, App Intents metadata, or stored focus calendar overrides.

## Permissions

AlertCalendar may request these macOS permissions:

- `Calendar`: read events, build the event queue, apply per-calendar alert rules, manage consolidated holidays, football fixtures, and game-sale campaigns, and reveal selected managed events in Calendar.
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
- Steamworks' public `partner.steamgames.com/doc/marketing/upcoming_events` page for announced seasonal and themed sale dates. No Steam login is required, and AlertCalendar does not store Steam account credentials. The page is HTML rather than a versioned API and may change.
- The public Xbox Wire Store and PlayStation Store RSS feeds for official sale announcements that include an explicit date range.
- Nintendo's public US news sitemap and matching official promotion articles for announced eShop campaigns with an explicit date range.
- Google Calendar's public iCalendar holiday feeds under `calendar.google.com` for the countries and territories selected in Settings.
- Slack API calls when Slack status sync is configured.
- `https://ipapi.co/json/` as an approximate location fallback when macOS Location permission is granted but Core Location does not return coordinates.
- Apple-backed geocoding/search via `CLGeocoder` and `MKLocalSearch` for map previews and structured football locations.

Local storage includes:

- User settings in `UserDefaults`.
- Slack connection data and tokens through the app's Slack/Keychain flow.
- Managed football event records.
- Managed game-sale event records and dismissed campaign identifiers.
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
│   ├── Models/
│   ├── Monitor/
│   ├── Settings/
│   ├── Slack/
│   └── System/
├── Features/
│   ├── Football/
│   ├── GameSales/
│   └── Holidays/
├── Resources/
├── Shared/
└── UI/
    ├── Menu/
    └── Settings/
        ├── Access/
        ├── Calendars/
        ├── General/
        ├── Integrations/
        └── State/
```

Important root files:

- `Package.swift`: Swift Package definition.
- `install.sh`: local release bundle builder/installer.
- `scripts/verify.sh`: local CI-style validation.
- `docs/architecture.md` and `scripts/check_architecture.sh`: architectural boundaries and their executable checks.
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

Keep tab-specific Settings code in its matching domain folder. Reserve `UI/Settings/Core` for the settings shell and cross-tab coordination, and keep `UI/Settings/State` free of UI/platform imports.

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

If Google holidays do not appear:

- Open Settings > Feeds > Holidays.
- Select one or more countries and a writable destination calendar, then apply the changes.
- Use `Use Subscribed` to select countries detected from existing Apple Calendar holiday subscriptions.
- Confirm Calendar access is granted. The feed refreshes weekly; use Refresh now for an immediate check.

If game-sale campaigns do not appear:

- Open Settings > Feeds > Game Sales and use Refresh.
- Confirm Calendar access is granted and a writable target calendar is selected.
- Confirm the Mac is online and enable Auto-add for each desired store; all four switches are off by default.
- Steam's official schedule is parsed defensively, but its HTML may change.
- Xbox, PlayStation, and Nintendo campaigns appear only when their official announcement includes both dates, so their lists can be incomplete.

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
