# Swim Club Analytics — Scarborough Summer Swimming Series

End-to-end SQL analytics project built on a relational database for a junior swim club. Captures four weeks of competition across six divisions, 85 swimmers, and 960 race-lane results, then layers a reusable view layer, advanced analytical queries, and a Power BI dashboard on top.

This project demonstrates relational data modelling, production-style data engineering, and analytical SQL applied to a real-world operational dataset.

---

## Status

| Phase | Scope                                                       | Status       |
|-------|-------------------------------------------------------------|--------------|
| 1     | Schema design · data extraction · one-command build         | ✅ Complete  |
| 2     | Reusable view layer · 12 advanced queries · notebook        | ✅ Complete  |
| 3     | Power BI dashboard (4 pages, direct SQLite ODBC connection) | 🔜 Next      |
| 4     | Polished docs and project write-up                          | 🔜 Planned   |

---

## What this project demonstrates

- **Data modelling** — 14-entity relational schema with referential integrity, CHECK constraints, and uniqueness rules that catch real data-entry errors.
- **Data engineering** — CSV extraction from a formula-heavy spreadsheet, silent cleaning fixes with full audit trail, idempotent one-command build.
- **Analytical SQL** — window functions (`LAG`, `DENSE_RANK`, `ROW_NUMBER`, running aggregates), CTE chains, anti-join gap analysis, and a reusable view layer that powers BI tools cleanly.
- **BI delivery** (Phase 3) — Power BI dashboard answering four business questions coaches, officials, and parents would actually ask.

---

## Quick start

Requires Python 3.9+ and the `openpyxl` package for the extraction step (the load step uses only Python's standard library).

```bash
# 1. Install the extractor's one dependency
pip install openpyxl

# 2. Re-extract CSVs from the source spreadsheet (optional — CSVs are committed)
python scripts/extract_from_xlsx.py path/to/source.xlsx data/

# 3. Build the SQLite database
python scripts/load_data.py

# Result: swim_club.db (~430 KB)
```

To inspect the database, use [DB Browser for SQLite](https://sqlitebrowser.org/) or any SQLite client.

---

## Repository layout

```
swim-club-analytics/
├── data/                               # Clean CSVs, one per entity
├── sql/
│   ├── 01_schema.sql                   # DDL — 14 tables with constraints
│   ├── 02_indexes.sql                  # Analytical-workload indexes
│   ├── 03_validation.sql               # Row counts + integrity checks
│   ├── 10_views.sql                    # 6 reusable views (dashboard layer)
│   └── 20_analytics.sql                # 12 advanced analytical queries
├── notebooks/
│   └── analytics_showcase.ipynb        # Narrated SQL walkthrough (renders on GitHub)
├── scripts/
│   ├── extract_from_xlsx.py            # Source → clean CSVs
│   └── load_data.py                    # CSVs → SQLite database
├── docs/
│   ├── design-notes.md                 # Schema decisions and data quality findings
│   ├── powerbi-setup.md                # Direct SQLite → Power BI via ODBC
│   └── erd-guide.md                    # Notes on the ERD
├── swim_club.db                        # Built database (after load)
└── README.md
```

---

## The SQL showcase

The best entry point is `notebooks/analytics_showcase.ipynb` — GitHub renders it inline so anyone can read the queries alongside their results without installing Jupyter. It covers:

- **Four business questions** answered by the dashboard (coach effectiveness, division leaderboards, swimmer trending, nomination-vs-actual)
- **Window function techniques**: `LAG`, `DENSE_RANK`, `ROW_NUMBER`, running aggregates with `ROWS BETWEEN UNBOUNDED PRECEDING`
- **CTE chains** to replace deeply-nested subqueries
- **Anti-join gap analysis** for the nomination data-quality finding

---

## Dataset at a glance

| Entity                         | Rows | Notes                                              |
|--------------------------------|-----:|----------------------------------------------------|
| Official                       |   13 |                                                    |
| Coach                          |    6 |                                                    |
| RoleType                       |    3 | Starter, Scrutineer, Results Official              |
| RacemeetInstance               |    4 | Weekly meets across Feb 2024                       |
| EventType                      |    5 | Freestyle, breaststroke, butterfly, backstroke, medley |
| LaneType                       |    8 | Lanes 1–8                                          |
| ResultType                     |   11 | 1st–8th place + DNS/DNF/DSQ                        |
| Division                       |    6 | Age 13/14/15 × Male/Female                         |
| Swimmer                        |   85 |                                                    |
| RacemeetEventInstance          |   20 | 5 events × 4 weeks                                 |
| RaceInstance                   |  120 | 30 races × 4 weeks                                 |
| RaceLaneInstance               |  960 | One row per lane per race                          |
| OfficialRacemeetRoleInstance   |   28 | Officials' weekly role assignments                 |
| NominationInstance             |  149 | Pre-race event sign-ups                            |

---

## Key findings surfaced by the analytics

- **636 races happened without a matching nomination** — strong signal that nomination capture is incomplete operationally.
- **Most swimmers set their personal-best freestyle time in Week 4**, suggesting training peaked correctly across the season.
- **Coach William Anthony's 14M division had a 0% DNF/DSQ rate** across 124 races — the strongest discipline metric of any coach.
- **15 swimmers raced without ever submitting a nomination**, while 13 nominations went unraced — both flagged for follow-up by club admin.

---

## Tech stack

SQLite · Python 3 (`openpyxl`, `pandas`) · Jupyter · Power BI · ODBC
