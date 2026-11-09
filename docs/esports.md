# Esports pilot

Esports is a separate feed under Settings. It reads gaming events from the selected Apple Calendar sources, including the active Focus filter, and distinguishes local calendar events from provider-managed encounters. Existing local events are never adopted or overwritten automatically.

The local catalog recognizes League of Legends, Counter-Strike 2, Rocket League, StarCraft II, Age of Empires II, GeoGuessr, and Gran Turismo 7. A local event retains its original title, date, calendar and source link. Detection does not invent participants or a score. Releases and maintenance remain ordinary gaming events rather than matches.

## Optional provider connection

PandaScore's free REST fixtures supply schedules, running/finished state, final results and streams for the first four games. Coverage must still be checked for each tournament. This pilot does not offer continuous map-by-map scores or WebSocket telemetry. AoE II, GeoGuessr and Gran Turismo remain available through their existing local calendar entries until another provider has been verified.

Connect a personal PandaScore token in the Esports pane. The credential is kept in a separate local Keychain service; it is never embedded in the application, saved in UserDefaults, added to URLs or included in calendar notes. Calendar titles and notes are classified locally. Only canonical game and match identifiers are requested from the provider. Provider views and managed event notes retain the attribution `Source: PandaScore`.

References: [overview](https://developers.pandascore.co/docs/introduction), [authentication](https://developers.pandascore.co/docs/authentication), [fixtures and plan capabilities](https://developers.pandascore.co/docs/plan-reference), [pricing and limits](https://www.pandascore.co/pricing).

## Calendar behavior

Choose a writable destination and alert policy. Card additions and removals are staged until Apply; Revert clears the staged operations. Automatic addition is opt-in by competition. A missing participant, uncertain date or incomplete provider response does not justify inventing a schedule or deleting an event.

Managed events use a provider/game/match identity separate from football. A failed EventKit transaction does not publish new ownership. Reads and refreshes preserve cached cards, and account/configuration changes invalidate stale asynchronous responses. Only events created and still owned by this integration can be removed by its card actions.

Local duplicate detection is conservative: same-game events with overlapping or nearby times are candidates for review, rather than proof of the same encounter. A candidate prevents automatic duplication and remains read-only. Managed encounters keep their own alert policy, independent of general per-calendar alert rules. Until an actual end time is supplied, their Calendar duration is explicitly estimated at two hours.

## Architecture

- `Features/Esports/Core`: provider-neutral models, catalog, REST adapter, parsing, request budget and actor-backed cache.
- `Core/Monitor/Esports`: local EventKit snapshots, managed records and lifecycle coordination.
- `Core/Settings/EsportsSettings.swift`: non-secret preferences and migration defaults.
- `Core/System/PandaScoreTokenKeychainStore.swift`: independent personal credential storage.
- `UI/Settings/Esports`: responsive cards, filters, connection state and staged calendar actions.

The pilot reuses shared HTTP cooldowns and synchronous Calendar mutation boundaries. It does not extend football-specific goals, stadiums, durations or home/away assumptions to other games.
