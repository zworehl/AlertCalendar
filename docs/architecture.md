# AlertCalendar Architecture

AlertCalendar is currently one SwiftPM executable target. Until the package is split into smaller targets, the codebase uses folder boundaries and import rules as the working architecture.

## Layers

- `Shared`: low-level models, formatting, clocks, and styling primitives used across the app. This is still transitional because some shared models carry `NSColor`.
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

## Rules Of Thumb

- Domain rules should accept explicit `Date`, `Calendar`, `Locale`, or settings inputs instead of reading global state.
- Parsing code should prefer typed `Decodable` envelopes. Dictionary parsing can remain where feeds are unstable, but it should be isolated behind parser helpers.
- SwiftUI views should render state and forward user intent. They should not normalize persisted settings or make broad domain decisions.
- Platform side effects should sit behind a named helper, service, or adapter. Direct calls to `UserDefaults.standard`, `URLSession.shared`, `NSWorkspace.shared`, `NSSound.beep()`, and `Process()` should not spread further.
- Routing and rule models should stay Foundation-only when possible; AppKit discovery helpers belong in adjacent catalog/launcher files.
- Any refactor should keep tests green at each checkpoint.

## Target Split Roadmap

The eventual SwiftPM target shape should be:

- `AlertCalendarShared`: pure utilities and models.
- `AlertCalendarDomain`: settings rules, menu bar state builders, alert rules, astronomy/football/slack pure logic.
- `AlertCalendarInfrastructure`: EventKit, Slack transport, ESPN transport, location, image/cache stores.
- `AlertCalendarUI`: SwiftUI/AppKit views and local presentation helpers.
- `AlertCalendarApp`: composition root and app entry point.

Do the split only after current import rules are clean enough that the move is mostly mechanical.
