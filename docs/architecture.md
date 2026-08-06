# AlertCalendar Architecture

AlertCalendar is currently one SwiftPM executable target. Until the package is split into smaller targets, the codebase uses folder boundaries and import rules as the working architecture.

## Layers

- `Shared`: platform-free foundational models, formatting, clocks, and styling values used across the app. Cross-feature composition models belong in `Core/Models`, not `Shared`.
- `Core`: domain services and platform integrations such as settings, calendar refresh, Slack, location, astronomy, system adapters, and the monitor coordinator.
- `Features`: feature-specific domain code. Football owns ESPN fetching, parsing, enrichment, fixture formatting, caches, and football-specific views.
- `UI`: SwiftUI and AppKit presentation code. UI may call monitor/coordinator entry points, but business rules should live in `Core`, `Features`, or small reducers.
- `App`: application bootstrapping, scene wiring, and macOS app delegate behavior.

## Current Direction

`CalendarMonitor` remains the app-facing coordinator, but new behavior should not add more state directly to it unless the state is truly cross-feature application state. Prefer extracting:

- Pure builders for presentation snapshots.
- Reducers for settings and UI draft transformations.
- Coordinators for feature side effects.
- Adapters for platform APIs and time.
- Runtime state structs for feature-specific coordinator state that still needs to be owned by `CalendarMonitor`.

## Source Map

- `App`: composition root, app delegate, scene wiring, and window metadata.
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

## Target Split Roadmap

The eventual SwiftPM target shape should be:

- `AlertCalendarShared`: pure utilities and foundational models.
- `AlertCalendarDomain`: settings rules, menu bar state builders, alert rules, astronomy/football/slack pure logic.
- `AlertCalendarInfrastructure`: EventKit, Slack transport, ESPN transport, location, image/cache stores.
- `AlertCalendarUI`: SwiftUI/AppKit views and local presentation helpers.
- `AlertCalendarApp`: composition root and app entry point.

Do the split only after current import rules are clean enough that the move is mostly mechanical.
