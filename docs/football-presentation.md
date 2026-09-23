# Football presentation

Team labels follow ESPN's `team.abbreviation`, the same provider used for fixtures. Preserve the complete published identifier after whitespace/punctuation normalization and uppercasing; do not force it to three characters. If the provider omits a code, show the available team name rather than inventing a broadcast abbreviation. Full names remain available in tooltips and detailed match headers.

The public ESPN team feeds checked on September 5, 2026 included `RMA` (Real Madrid), `ATM` (Atlético Madrid), `MNC` (Manchester City), `MAN` (Manchester United), and the four-character `REMO` (Remo). These are provider conventions, not a claim that every television broadcaster uses identical graphics or codes. RTÉ's Barcelona–Bayern coverage uses BAR/BAY, while Bayern's own match center uses FCB. Mixing abbreviations from different providers could introduce inconsistencies or collisions.

Sources:

- [ESPN Spanish league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams?limit=1000)
- [ESPN English league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams?limit=1000)
- [ESPN Brazilian league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/teams?limit=1000)
- [RTÉ Barcelona–Bayern match coverage](https://www.rte.ie/sport/results/soccer/champions-league/24110/report-4621509/)
- [Bayern's official match center](https://fcbayern.com/es/match-center/matchplan/profis)

Goal scorer coverage varies by match. A published score does not imply that ESPN has published the scorer, minute, lineup, or play-by-play. The Alajuelense–Saprissa summary for event `401876857` had a 0–1 halftime score but no `keyEvents` or `scoringPlays`; the core play-by-play collection was also empty when checked. In this case the UI shows an explicit unavailable state and Retry. It must never infer a scorer from the score or team roster.

Loading retries are bounded and keyed to the match, score, and lifecycle state, rather than the live minute. Optional athlete nationality requests do not block the initial display of scorer names.

## Calendar flags

Resolve team details before saving scheduled fixtures too. Country lookup can use domestic team/group references when ESPN omits the venue. Incomplete country data expires after 15 minutes instead of the complete-team cache's 30 days, so a temporary omission does not leave white flags in Calendar for weeks.

Some ESPN club records have no domestic reference or expose a foreign touring venue. `FootballClubCountryResolver` keeps a small verified fallback keyed by both ESPN ID and recognized club name. It never assigns a country from a competition shared by several countries or from a similarly named club.

| ESPN ID | Club | Country | Verification |
| --- | --- | --- | --- |
| 493 | Shakhtar Donetsk | Ukraine | [UEFA club facts](https://www.uefa.com/uefaeuropaleague/news/024c-0e994115062c-933d0abff424-1000--club-facts-shakhtar-donetsk/) |
| 494 | Slavia Prague | Czech Republic | [UEFA club profile](https://www.uefa.com/uefachampionsleague/clubs/52498/) |
| 521 | Slovan Bratislava | Slovakia | [UEFA national association profile](https://www.uefa.com/nationalassociations/teams/52797--slovan-bratislava/) |
| 21922 | Sabah FK | Azerbaijan | [UEFA club profile](https://www.uefa.com/uefachampionsleague/clubs/2609356/squad/) |

Checked on September 5, 2026. The ESPN team records for [Real Madrid](https://sports.core.api.espn.com/v2/sports/soccer/teams/86?lang=en&region=us), [Napoli](https://sports.core.api.espn.com/v2/sports/soccer/teams/114?lang=en&region=us), [PSV](https://sports.core.api.espn.com/v2/sports/soccer/teams/148?lang=en&region=us), and [Luis Ángel Firpo](https://sports.core.api.espn.com/v2/sports/soccer/teams/7232?lang=en&region=us) already supplied their countries; stale incomplete cache entries had prevented those flags from recovering.
