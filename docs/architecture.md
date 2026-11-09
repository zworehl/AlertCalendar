# AlertCalendar Architecture

AlertCalendar is currently one SwiftPM executable target. Until the package is split into smaller targets, the codebase uses folder boundaries and import rules as the working architecture.

## Layers

- `Shared`: platform-free foundational models, formatting, clocks, and styling values used across the app. Cross-feature composition models belong in `Core/Models`, not `Shared`.
- `Core`: domain services and platform integrations such as settings, calendar refresh, Slack, location, astronomy, system adapters, and the monitor coordinator.
- `Features`: feature-specific domain code. Football owns ESPN fetching, parsing, enrichment, fixture formatting, caches, and football-specific views.
- `UI`: SwiftUI and AppKit presentation code. UI may call monitor/coordinator entry points, but business rules should live in `Core`, `Features`, or small reducers.
- `App`: application bootstrapping, window composition, and macOS app delegate behavior.

## Current Direction

`CalendarMonitor` remains the app-facing coordinator, but new behavior should not add more state directly to it unless the state is truly cross-feature application state. Prefer extracting:

- Pure builders for presentation snapshots.
- Reducers for settings and UI draft transformations.
- Coordinators for feature side effects.
- Adapters for platform APIs and time.
- Runtime state structs for feature-specific coordinator state that still needs to be owned by `CalendarMonitor`.

## Source Map

- `App`: composition root, app delegate, window presentation, and window metadata.
- `Shared`: Foundation-only primitives with no dependency on feature or platform integration types.
- `Core/Models`: application-level composition models that intentionally connect multiple features.
- `Core/Monitor`: the app-facing coordinator, grouped by side-effect or feature integration.
- `Core/Settings`: persisted settings, normalization, and pure settings rules.
- `Core/System`: wrappers around macOS process, workspace, sound, notification, and HTTP APIs.
- `Features/<Feature>/Core`: feed clients, parsers, caches, and feature-domain models.
- `Features/<Feature>/UI`: feature-specific reusable presentation.
- `UI/Menu`: menu bar and contextual presentation.
- `UI/Settings`: the settings shell plus domain folders such as `General`, `Calendars`, `Integrations`, `Access`, and `State`.

`UI/Settings/Core` is reserved for the settings shell and cross-tab coordination. New tab-specific code should go into its matching domain folder. `UI/Settings/State` must remain Foundation-only.

`UI/Settings/Shared` owns reusable visual primitives. Labeled dropdowns should use `SettingsLabeledMenuPicker`, every writable-calendar destination labeled `Add To` should use `SettingsAddToCalendarPicker`, peer checkbox collections should use `SettingsLabeledCheckboxGroup`, and calendar-backed cards should use `SettingsCalendarCardActionButton` for add, remove, and open actions. These shared controls keep label width, typography, spacing, responsive wrapping, help affordances, card actions, and accessibility consistent across features. Use `SettingsVerticalDivider` only between distinct control groups that share a horizontal row; switch to a horizontal divider when those groups stack.

`AlertCalendarDateRangeFormatter.compactAllDayRange` is the single compact all-day range formatter used by the dropdown and settings cards. Game store presentations should resolve their platform artwork and brand colors through `GameStoreSymbolProvider` and `GameStoreIconView` so the menu and settings use the same assets.

## Rules Of Thumb

- Domain rules should accept explicit `Date`, `Calendar`, `Locale`, or settings inputs instead of reading global state.
- Parsing code should prefer typed `Decodable` envelopes. Dictionary parsing can remain where feeds are unstable, but it should be isolated behind parser helpers.
- SwiftUI views should render state and forward user intent. They should not normalize persisted settings or make broad domain decisions.
- Platform side effects should sit behind a named helper, service, or adapter. Direct calls to `UserDefaults.standard`, `URLSession.shared`, `NSWorkspace.shared`, `NSSound.beep()`, and `Process()` should not spread further.
- Routing and rule models should stay Foundation-only when possible; AppKit discovery helpers belong in adjacent catalog/launcher files.
- Shared types must not refer to feature-specific models. Put cross-feature application composition in `Core/Models`.
- Source files should stay at or below 500 lines and test files at or below 1,000 lines.
- Any refactor should keep tests green at each checkpoint.

## Menu presentation

AppKit owns the application lifecycle, the status item, and the Settings window; SwiftUI renders their contents. `MenuBarController` is the sole owner of the dropdown panel's visibility, keyboard focus, and anchored size. One status-button action toggles the panel on mouse-down. Content actions dismiss through `MenuDropdownActions`, including Settings, meeting links, and About. Outside-click monitoring excludes the status button, dropdown children, and native menu tracking windows. No private AppKit/SwiftUI method interception or synthetic begin/cancel sessions are used. The expanded-interface delegate is deliberately not installed: on the tested macOS 27.2 build, its host ends the session on the closing mouse-down and begins another on mouse-up, reopening the panel and activating the app.

`MenuBarStatusItemLabelRenderer` observes the menu presentation model independently from the panel. Updating badge artwork, loading frames, or football logos never presents or activates a window. `MenuDropdownWindowObserver` reports visibility and display constraints; it does not reposition the window. The controller anchors content height changes at the status item and clamps the frame to the selected display in desktop points.

## Automation and blocking operations

Apple Events and automation permission probes run in disposable child processes of the signed AlertCalendar executable, before SwiftUI or the monitor is initialized. `AlertCalendarAutomation` permits one operation per target application and rejects overlapping work instead of queuing it. Each process has a deadline, bounded output, separate stdout/stderr, and cancellation that kills the child. A stuck Mail operation cannot block Music, a browser, Calendar, or the main actor.

`AppleMailAutomationPermission.currentStatus()` reads a cached value and schedules a coalesced refresh. Settings await permission updates asynchronously. Passive probes never request consent; only the explicit request-access action does so. Mail context falls back to the event's own context when access or automation is unavailable. Music observation failures are distinct from stopped playback and appear in Slack diagnostics.

The Slack watchdog measures time without progress rather than the total duration across workspaces. Canceled requests cannot commit stale sync state. New automation integrations must use the helper; direct `NSAppleScript` execution and permission probes elsewhere are rejected by the architecture check. Waiting subprocess calls must use the asynchronous, bounded `AlertCalendarProcessRunner.runCapturingOutput` API.

## Target Split Roadmap

The eventual SwiftPM target shape should be:

- `AlertCalendarShared`: pure utilities and foundational models.
- `AlertCalendarDomain`: settings rules, menu bar state builders, alert rules, astronomy/football/slack pure logic.
- `AlertCalendarInfrastructure`: EventKit, Slack transport, ESPN transport, location, image/cache stores.
- `AlertCalendarUI`: SwiftUI/AppKit views and local presentation helpers.
- `AlertCalendarApp`: composition root and app entry point.

Do the split only after current import rules are clean enough that the move is mostly mechanical.

## Calendar mutation boundaries

Esports has a separate `EsportsRuntime` and domain models. Its native Calendar adapter reads selected, Focus-visible sources; a provider match is never inferred from a local title. Possible local duplicates remain read-only. The optional personal REST connection uses a revisioned credential vault, an actor-backed cache and the shared HTTP recovery policy. Calendar ownership is recorded only after a committed mutation, and generic calendar alert rules leave managed esports alarms to the feed's own policy. See [the esports pilot](esports.md).

`CalendarMutationCoordinator` stages and commits a synchronous batch without yielding the main actor. A failed save, removal, or commit resets the store before the monitor publishes ownership changes. Managed football records remain available during temporary read or write failures. `CalendarAlertFullSyncCoordinator` persists completed date windows per rules fingerprint, retries only pending windows with bounded backoff, and writes the final completion marker only after all windows succeed.

## Persistence and optional enrichment

`CalendarCacheRepository` owns JSON cache loading and steady-state writes outside the presentation actor. Bootstrap and UI requests share one restore task; restored snapshots cannot replace newer in-memory results. Title writes are coalesced. Normal termination waits for the same serialized cache repository to finish pending football and title snapshots; a closing barrier rejects late background writes.

`FootballLogoLoadingCoordinator` publishes optional artwork after fixture data without delaying the calendar refresh. Image and team lookups coalesce concurrent requests; temporary team failures have a short negative cache. Decoded UI logos are limited to 192 pixels and the shared image cache has a 24 MiB cost budget.

## Network health and verification

`HTTPServiceTransport` applies per-host request limits and provider cooldowns for Slack, game sales, holidays, and images. HTTP success, validated data, and applied snapshots are separate metrics; partial updates retain source failures and show the oldest active validated data. Holiday recovery retains successful countries and protects unavailable-country events from deletion.

The packaged executable supports an internal `--smoke-test --report <path>` mode before normal startup and the instance lock. It uses isolated defaults, disabled live services, an offline URL protocol, and actual menu/Settings surfaces. It validates menu visibility, multiple widths and languages, permission-denied/offline presentation, and draft transformations without accessing live integrations.
