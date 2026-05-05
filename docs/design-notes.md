# Design Notes & Data Quality Findings

This document captures the schema design decisions made during the build, plus three real data-quality issues uncovered when the constraints were applied to the source data. It's intended for anyone reading the repo who wants to understand *why* the schema looks the way it does.

## Schema design choices

### Identifier style

All primary keys use a `camelCase` short-form pattern (`swimmerID`, `raceLaneInstanceID`). The instance suffix is deliberate on tables like `RaceInstance` and `RacemeetEventInstance` — it distinguishes a specific race/event occurrence from its abstract type (`EventType`, `RoleType`).

### Constraint philosophy

Three tiers of constraints applied:

1. **Domain constraints** (CHECK) — every enum-like column is validated at the database level: `gender IN ('M','F')`, `activeStatus IN ('ACTIVE','INACTIVE')`, `strokeType IN ('freestyle', 'breaststroke', 'butterfly', 'backstroke', 'medley')`, etc. This means bad data fails at insert time, not at query time.

2. **Referential integrity** (FK) — all relationships enforce valid parent rows. SQLite requires `PRAGMA foreign_keys = ON;` per connection, which the load script sets explicitly.

3. **Business rules** (UNIQUE composite) — `RaceLaneInstance` has `UNIQUE (raceInstanceID, swimmerID)` and `UNIQUE (raceInstanceID, laneTypeID)`, encoding the rules that a swimmer can't be in two lanes of the same race, and two swimmers can't share a lane. Similarly, `NominationInstance` has `UNIQUE (swimmerID, racemeetEventInstanceID)` so a swimmer can't nominate twice for the same event.

The third tier is what catches the data quality issues documented below.

### NULL handling in RaceLaneInstance

`RaceLaneInstance.swimmerID` and `resultTypeID` are nullable. This represents empty lanes — races where fewer than 8 swimmers competed. Modelling these as NULL rather than dropping the rows preserves total-lane and utilisation analytics (see Q10 in `sql/20_analytics.sql`).

### View layer as the BI boundary

Six views in `sql/10_views.sql` form the semantic layer between the normalised schema and downstream consumers (the notebook, Power BI). This is deliberate:

- Schema changes don't break the dashboard — they require updating the relevant view only.
- Power BI sees clean, denormalised data and doesn't need to construct joins itself.
- The same views power both ad-hoc analysis and scheduled reporting.

`v_race_results` is the central fact table — every dimension joined and unpacked. The other five views are aggregations or filtered slices.

## Data quality findings

Three real issues were uncovered when the source data was loaded against the constraints. All three are silently fixed during extraction (`scripts/extract_from_xlsx.py`) and documented here.

### Finding 1 — Inconsistent swimmer ID format across sources

The source `NominationInstance` records used swimmer IDs in format `swmr1`, `swmr2`, …, `swmr85` (not zero-padded), while every other source used `swmr01`, `swmr02`, …, `swmr85` (zero-padded). Without a fix, every FK reference from nominations to swimmers would fail for single-digit IDs.

**Resolution:** normalised all swimmer IDs to the zero-padded format during CSV extraction. After the fix, all 149 nominations resolve to valid swimmers.

### Finding 2 — Duplicate swimmer entries in backstroke races

Loading the data with the `UNIQUE (raceInstanceID, swimmerID)` constraint immediately flagged that **swimmer `swmr85` (Kendrick Lu) appears in both lane 1 and lane 6 of every 50m backstroke race for the 13-year-old boys division, across all four weeks** — 4 duplicate records in total.

Cross-referencing the nomination table confirmed `swmr85` never nominated for backstroke, strongly suggesting the lane 6 entries were data-entry errors.

**Resolution:** kept the first occurrence (lane 1) and nulled the `swimmerID` and `resultTypeID` on the duplicate (lane 6) entries. The lane rows are preserved with their timing data intact — the lane is simply marked as "unknown swimmer" rather than falsely attributed.

This is a textbook case for why composite UNIQUE constraints matter. Without them, every per-swimmer aggregation downstream would be silently inflated for `swmr85`.

### Finding 3 — Duplicate nomination record

A single nomination was recorded twice in the source (both `nom23` and `nom46` recorded `swmr21` nominating for `rmev001` on 2024-02-01).

**Resolution:** deduplicated on `(swimmerID, racemeetEventInstanceID)`, keeping the first occurrence. Final count: 149 nominations.

## Data "features" preserved (not bugs)

These were considered for fixing but deliberately kept as-is because they reflect real-world swim admin:

- **188 NULL swimmer/result rows in RaceLaneInstance** — represent empty lanes in races with fewer than 8 swimmers (plus the 4 nulled-out duplicates from Finding 2). Preserved rather than dropped so total-lane and utilisation queries are possible.
- **15 swimmers who raced without nominating** — reflects real-world late-entries or on-the-day additions. Preserved as a genuine analytical finding surfaced on the dashboard.
- **Two pairs of duplicate swimmer names** (Madison Heart × 2, Margaret Jones × 2) — different swimmer IDs, different birthdates, genuinely different people. Names are not unique identifiers.

## Type coercion

`Swimmer.age` was stored as a TEXT string (`'13'`) in the source while `Division.age` was stored as a number. Unified as INTEGER in the database schema for arithmetic operations to work correctly downstream.
