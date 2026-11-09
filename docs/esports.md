# Esports pilot

Esports is a separate feed under Settings. It reads gaming events from the selected Apple Calendar sources, including the active Focus filter, and distinguishes local calendar events from provider-managed encounters. Existing local events are never adopted or overwritten automatically.

The browser follows the football feed's layout: encounter cards and destination controls occupy the main column, while a right sidebar holds the view mode, date window, game and competition lists. The optional provider connection stays available in that sidebar.

The supported catalog is League of Legends, Counter-Strike 2, Rocket League and StarCraft II. The Esports browser classifies local competitive events only for those four games. A local event retains its original title, date, calendar and source link. Detection does not invent participants or a score. Releases and maintenance remain ordinary gaming events rather than matches.

## Optional provider connection

PandaScore's free REST fixtures supply schedules, running/finished state, final results and streams for those four games. Coverage must still be checked for each tournament. This pilot does not offer continuous map-by-map scores or WebSocket telemetry.

Age of Empires II, GeoGuessr and Gran Turismo 7 are excluded from the Esports catalog and its local classification because a usable fixture feed was not verified. Their manual events remain unchanged in Apple Calendar and the application's general agenda, subject to the normal calendar and Focus filters. Removing a game from the catalog does not delete, edit or migrate its events. Legacy game identifiers remain decodable for stored-data compatibility.

Connect a personal PandaScore token in the Esports pane. The credential is kept in a separate local Keychain service; it is never embedded in the application, saved in UserDefaults, added to URLs or included in calendar notes. Calendar titles and notes are classified locally. Only canonical game and match identifiers are requested from the provider. Provider views and managed event notes retain the attribution `Source: PandaScore`.

References: [overview](https://developers.pandascore.co/docs/introduction), [authentication](https://developers.pandascore.co/docs/authentication), [fixtures and plan capabilities](https://developers.pandascore.co/docs/plan-reference), [pricing and limits](https://www.pandascore.co/pricing).

### Review of the other requested games

The November 2026 review found these sources, without establishing a documented, usable feed for competitive fixtures:

- **Age of Empires II:** [AoE2 Live Standings API](https://github.com/ag-tech-group/aoe2-live-standings-api) describes tournament rosters, player ratings, match history and live-game data; that does not establish upcoming bracket fixtures for The League or The Garrison. The [official Garrison event page](https://www.ageofempires.com/events/the-garrison-2026/) provides event information rather than a verified per-match feed.
- **GeoGuessr:** the [official World Championship page](https://www.geoguessr.com/world-championship/berlin) and [Wildcard page](https://www.geoguessr.com/world-championship/wildcards) publish human-readable schedules and results. No public documented ICS/JSON/API feed with an established integration contract was found; direct automated retrieval returned HTTP 403 during the review.
- **Gran Turismo 7:** the [official championship site](https://www.gran-turismo.com/us/gt7/championships/2026/) and [Singapore results](https://www.gran-turismo.com/us/gt7/events/gtws2026/singapore/race_result/) provide official event and result pages. No documented public fixture API, JSON feed or calendar subscription was verified.

These are findings about verified integration coverage, not a claim that no API could exist. The application does not use reverse-engineered sessions, bypass access controls or treat a web page as a stable data-provider contract.

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
