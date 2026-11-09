# Football presentation

Team labels use at most three uppercase characters across match cards, the menu bar, probabilities, notifications, and Calendar titles. `FootballTeamBroadcastCode` applies reviewed compact labels before falling back to short ESPN codes or a compact name. Full names remain available in tooltips and detailed match headers.

The October 14, 2026 audit covers all 548 distinct teams returned by the 28 supported competition feeds. The checked catalog is retained as a test fixture with provider identifiers, expected display codes, and source URLs. Reviewed labels include MUN/MCI for Manchester United/City, BAY for Bayern, ROM for Roma, TIG/PUM for Tigres/Pumas, and SCA for AD San Carlos. ESPN gives AD San Carlos and Inter de San Carlos the same short name; their IDs keep SCA and ISC distinct. Name aliases are used only when they identify one reviewed code. Previous provider codes remain valid during Calendar event recovery, including mixed old/new labels if the provider adopts a reviewed code later.

The November 1, 2026 code review adds LDA/CSC/CSH/PFC/SFC in Costa Rica, AFC for Alianza of Panama (the Salvadoran Alianza keeps ALI), CLT for Celta (Celtic keeps CEL), BVB, MIX, CCP, ONC, SAL, URD, UHD, and WAC. Generic shared names such as Alianza and Deportivo require a matching ESPN identity. National labels use NCL, SDN, LBN, SGP, and GLP; flag resource aliases keep legacy SIN/GDL asset names separate from display labels.

Sources:

- [Premier League team data and official short names](https://fantasy.premierleague.com/api/bootstrap-static/)
- [ESPN Costa Rican league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/crc.1/teams?limit=1000)
- [ESPN Spanish league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams?limit=1000)
- [ESPN English league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams?limit=1000)
- [ESPN Brazilian league team feed](https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/teams?limit=1000)
- [RTÉ Barcelona–Bayern match coverage](https://www.rte.ie/sport/results/soccer/champions-league/24110/report-4621509/)
- [Bayern's official match center](https://fcbayern.com/es/match-center/matchplan/profis)
- [Cartaginés official fixtures and standings](https://cscartagines.com/)
- [Concacaf Central American Cup clubs and codes](https://www.concacaf.com/competitions/central-american-cup/clubs/alianza-f.c)
- [Celta UEFA profile and fixtures](https://www.uefa.com/uefaeuropaleague/clubs/53043--celta/)
- [Dortmund Bundesliga profile](https://www.bundesliga.com/en/bundesliga/clubs/borussia-dortmund)
- [Cerro Porteño CONMEBOL match](https://gol.conmebol.com/es/fixture/view/544)
- [Once Caldas official match announcement](https://www.oncecaldas.com.co/boleteria-vs-racing-uru)
- [FIFA Club World Cup participant abbreviations](https://gpcustomersupportfcwc2025.tickets.fifa.com/hc/en-us/articles/23802248983453-3-Which-clubs-are-participating-in-the-FIFA-Club-World-Cup-2025)
- [FIFA national association codes](https://inside.fifa.com/associations/LBN)
- [Concacaf Guadeloupe profile](https://www.concacaf.com/inside-concacaf/member-associations/guadeloupe)

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
