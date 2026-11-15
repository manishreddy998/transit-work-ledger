# transit-work-ledger

[![build](https://github.com/manishreddy998/transit-work-ledger/actions/workflows/build.yml/badge.svg)](https://github.com/manishreddy998/transit-work-ledger/actions/workflows/build.yml)

**Every scheduled hour of Toronto transit, and which minutes of it were lost, to what, on which route and which vehicle. A deterministic data foundation first, then an AI layer that can only say what the data says.**

Built on public City of Toronto open data: the TTC's current GTFS timetable and every bus, streetcar and subway delay logged since January 2025 (179,642 events). The logs are what operations data usually looks like: three teams, three file layouts, 695 different spellings of about 200 bus routes, codes missing from the TTC's own code list, broken characters, vehicle number 0 for "unknown", and repeated lines.

```bash
make setup && make download && make all     # ~45 MB of public data, then the build and its tests
.venv/bin/python -I scripts/ask.py "Which streetcar route lost the most service, and why?"
```

## What it found

| | |
|---|---|
| Delay minutes logged, Jan 2025 to Sep 2026 | **47,769 hours** |
| Counted as lost service | **28,454 hours**. Diversions and shuttle redeployments are left out: diversion events log how long a detour lasted (122 minutes on average), not a delay, and would overstate lost time |
| Within the TTC's own control | **15,912 hours (56%)**: vehicle equipment, staffing, operations, track and power, on-board systems |
| Biggest controllable cause | Vehicle equipment, **8,651 hours** |
| Bus routes losing the most | 52 Lawrence West (642 h, 67% within TTC control), 102 Markham Rd (464 h, 75%), 97 Yonge (422 h, 0.53% of planned hours, the highest share of the three) |
| Streetcar | 504 King lost 998 hours, but only 27% of it was within the TTC's control. Customers and traffic cost it more than its own equipment |
| Vehicles that keep failing | 182 vehicles had 20 or more equipment faults within 30 days of the previous one. Bus 1233: 60 faults, 54 of them repeats |

Every number above comes out of the SQL in `models/` and can be traced to the rows behind it.

## How the data is made trustworthy

| Mess in the logs | Rule | Where |
|---|---|---|
| 695 spellings of bus routes: `52 LAWRENCE WEST`, `52`, `52B LAWRENCE WEST` | Route number plus a check that the name matches the timetable's route name | `int_line_resolution` |
| `52 BURNHAMTHORPE`: the number says one route, the name another | Left **empty** and sent to review. Not guessed | `number_name_conflict` |
| `52 LAWRENCE WEST & 952`, `YU/BD`: two lines in one field | Left empty and sent to review | `several_routes_listed` |
| `LINE 1 SHUTTLE` in the bus log | Counted against subway Line 1, the service the buses replaced | `shuttle_replacing_subway` |
| A bus logged on `504 KING`, a streetcar route | Counted on route 504 and marked as another mode's vehicle | `other_mode_vehicle` |
| `999`, `600`, `RAD`, `TRAINING BUS`, `SRT` (closed 2023) | Not public routes. Route left empty, with the reason written down | `seeds/not_public_routes.csv` |
| 12,405 events use codes missing from the code list | Cause taken from the code's first letter (the TTC convention: E equipment, T transportation, P plant, S security, M miscellaneous) and marked as inferred | `int_causes` |
| "Miscellaneous" codes hiding real causes | Description rules: no operator = staffing, diversion, shuttle, congestion, VISION on-board systems, weather | `seeds/cause_rules.csv` |
| Vehicle number 0 on 25,957 events | Vehicle left empty. There is no vehicle 0 in the asset list | `stg_delays` |
| `ILL CUSTOMER â TRANSPORTED` | Repaired to an en dash, not dropped | `fix_mojibake` |
| 386 exact repeated log lines | Kept once | `int_events` |

`rules.cause_groups` writes down which causes count as lost time and which are within the TTC's control, with a reason for each, so the headline number can be argued with instead of taken on faith.

## The AI layer

`scripts/ask.py` answers plain-English questions with Claude (`claude-opus-5-5`), but the model never writes SQL. It can only call six fixed, parameterized, read-only tools: `lost_time_by_route`, `causes_for_route`, `vehicle_history`, `repeat_fault_vehicles`, `data_quality` and `counting_rules`. After it answers, every number in the answer is checked against the numbers the tools returned. A figure no tool produced is printed under `UNVERIFIED` instead of passing as fact. `python scripts/ask.py --tools-only` runs every tool without calling the model.

## Tests

`dbt build` runs the models and 9 tests, including:

- **8 real cases checked by hand** (`tests/assert_golden_cases.sql`): 52 BURNHAMTHORPE stays unplaced, LINE 1 SHUTTLE counts against Line 1, a bus on 504 King is marked as another mode's vehicle, two listed routes stay unplaced, no vehicle 0 exists, diversions add no lost time, no-operator codes are staffing, the broken en dash is repaired.
- **The ledger adds up:** lost minutes per route-day equal the event total, to the minute.

## Honest limits

- Planned hours come from the **current** timetable (Nov to Dec 2026) applied by day type. They are a baseline for past days, not each day's exact plan.
- A delay's minutes are recorded for one vehicle. A subway delay holds up the trains behind it too, so subway lost time is understated.
- Cause groups follow the code each operator chose. A miscoded event lands in the wrong group, and the rules can't see that.
- Run `select * from reports.rpt_review_queue` for everything the rules could not decide.

## Layout

```
scripts/download.sh, load.py   fetch and land the files as published, with SHA-256 and row counts
scripts/ask.py                 the AI layer: fixed SQL tools plus a number check on every answer
seeds/                         every rule: cause prefixes, description rules, cause groups, subway codes, non-public routes
models/staging/                the three delay logs in one shape, code lists repaired, timetable trips with durations
models/intermediate/           line resolution, cause rules, events with quality flags
models/marts/                  fct_delay_event, fct_route_day, fct_vehicle, dim_route, metric_lost_time_monthly
models/reports/                rpt_data_quality, rpt_review_queue
```

Data: City of Toronto Open Data (TTC Routes and Schedules, TTC Bus, Streetcar and Subway Delay Data), Open Government Licence - Toronto.

---

Built by Manish Reddy, Data/AI Engineer in Toronto. [LinkedIn](https://www.linkedin.com/in/manish-re-50c02a719k/) · [GitHub](https://github.com/manishreddy998)
