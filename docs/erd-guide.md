# Entity-Relationship Model

The Scarborough Summer Swimming Series schema has 14 entities organised into three layers: reference/lookup tables, core domain entities, and transactional event tables.

## Entity overview

### Reference / lookup tables

These hold static or slowly-changing reference data with no foreign key dependencies of their own.

| Entity     | Purpose                                              |
|------------|------------------------------------------------------|
| Official   | Race officials (timekeepers, scrutineers, etc.)      |
| Coach      | Coaches assigned to divisions                        |
| RoleType   | The three official role types (Starter, Scrutineer, Results Official) |
| EventType  | The five swimming events (50m freestyle, 50m breaststroke, 50m butterfly, 50m backstroke, 4×50m medley) |
| LaneType   | The eight available pool lanes                       |
| ResultType | The eleven possible race outcomes (1st–8th place + DNS/DNF/DSQ) |
| RacemeetInstance | Each weekly racemeet (4 across the season)     |

### Core domain entities

These are the central business objects with relationships into both the reference data and the event data.

| Entity   | Belongs to | Notes                                |
|----------|------------|--------------------------------------|
| Division | Coach      | Six divisions (13/14/15 yo × M/F)    |
| Swimmer  | Division   | 85 swimmers across the six divisions |

### Transactional / event tables

These capture the actual events of the season — what happened, when, and to whom.

| Entity                          | Captures                                        |
|---------------------------------|-------------------------------------------------|
| RacemeetEventInstance           | An event scheduled in a racemeet (e.g. 50m freestyle in week 1) |
| RaceInstance                    | A specific race within an event (one per division per event)    |
| RaceLaneInstance                | One row per lane per race — the analytical fact table           |
| OfficialRacemeetRoleInstance    | Which official held which role at which racemeet                |
| NominationInstance              | Pre-race event sign-ups                                         |

## Key relationships

```
Coach                                Official
  │ 1                                  │ M
  │                                    │
  │ M                                  │
Division ──────┐                       │
  │ 1          │                       ├───── OfficialRacemeetRoleInstance
  │            │ 1                     │ M
  │ M          ▼                       │
Swimmer    RaceInstance                ▼
  │            │ 1                  RoleType (M)
  │            │
  │ M          │ M
  ├──────► RaceLaneInstance              RacemeetEventInstance
  │            ▲                            │ 1                ▲
  │            │ M                          │                  │
  │ M          │                            │ M                │ M
  ├────► NominationInstance ◄───────────────┘                  │
  │            ▲                                               │
  │            └──────────────────────────────────────────────RacemeetInstance
  │
  └────► (also linked to LaneType, ResultType through RaceLaneInstance)
```

## Notable design choices

### Three-table chain for race results

The hierarchy is **`RacemeetEventInstance` → `RaceInstance` → `RaceLaneInstance`**, not a flat structure. This mirrors how a real swim club organises a meet:

- A **RacemeetEventInstance** is a scheduled event (e.g. "50m freestyle, week 1, 5:30 PM").
- A **RaceInstance** is a specific race within that event (one per division — six divisions race the same event back-to-back).
- A **RaceLaneInstance** is a single lane within a race — eight per race, one per swimmer (or NULL if the lane was empty).

This three-tier design lets the same event run for multiple divisions without duplicating event metadata, and lets each lane carry its own time and result independently.

### NominationInstance ↔ RacemeetEventInstance, not RaceInstance

Swimmers nominate for an *event* (e.g. "50m freestyle, week 1"), not for a specific race within that event — they don't pick which division-heat they want, that's allocated automatically based on their division. This is why the FK from `NominationInstance` points to `RacemeetEventInstance`, not `RaceInstance`.

### The OfficialRacemeetRoleInstance bridge

This is a three-way bridge table connecting Officials, Racemeets, and RoleTypes. The composite PK `(officialID, racemeetInstanceID)` enforces that an official has one role per racemeet — they don't double up as both a Starter and a Scrutineer at the same meet.

## Drawing the ERD yourself

If you want to draw or re-draw the ERD diagrammatically:

- **draw.io / diagrams.net** (https://app.diagrams.net) — runs in browser, no account, has built-in ER shape library. The fastest free option.
- **dbdiagram.io** (https://dbdiagram.io) — text-based ERD generator. You describe the schema in a mini-language and it auto-draws. Good if you prefer code over clicking.
- **DBeaver** (free SQL client) — can auto-generate an ERD by inspecting the SQLite database directly. Lowest effort but the auto-layout is sometimes ugly.

Save your final diagram as `docs/ERD.png` and the README will pick it up automatically.
