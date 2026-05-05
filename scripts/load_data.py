"""
load_data.py
------------
Build the SQLite database from scratch:
  1. Execute 01_schema.sql to create tables
  2. Bulk-load each CSV into its matching table
  3. Execute 02_indexes.sql for analytical-query performance
  4. Enable and verify foreign-key constraints

After a successful run the database lives at swim_club.db in the project root.

Usage (from project root):
    python scripts/load_data.py
"""

import csv
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "swim_club.db"
SQL_DIR = ROOT / "sql"
DATA_DIR = ROOT / "data"

# CSV filename -> (table name, column list). Order matters: parents before children.
LOAD_ORDER = [
    ("officials.csv",                   "Official",
        ["officialID", "firstName", "lastName", "employeeStartDate", "activeStatus"]),
    ("coaches.csv",                     "Coach",
        ["coachID", "firstName", "lastName", "employeeStartDate"]),
    ("role_types.csv",                  "RoleType",
        ["roleTypeID", "roleTitle", "roleDescription", "numberRequired"]),
    ("racemeet_instances.csv",          "RacemeetInstance",
        ["racemeetInstanceID", "weekOfCompetition", "racemeetDate", "startTime"]),
    ("event_types.csv",                 "EventType",
        ["eventTypeID", "eventDescription", "strokeType",
         "distancePerLeg", "numberOfLegs", "individualOrMedley"]),
    ("lane_types.csv",                  "LaneType",
        ["laneTypeID", "laneNumber"]),
    ("result_types.csv",                "ResultType",
        ["resultTypeID", "positionResult", "points"]),
    ("divisions.csv",                   "Division",
        ["divisionID", "age", "gender", "coachID"]),
    ("swimmers.csv",                    "Swimmer",
        ["swimmerID", "firstName", "lastName", "dob", "age", "gender", "divisionID"]),
    ("racemeet_event_instances.csv",    "RacemeetEventInstance",
        ["racemeetEventInstanceID", "startTime", "racemeetInstanceID", "eventTypeID"]),
    ("race_instances.csv",              "RaceInstance",
        ["raceInstanceID", "startTime", "poolLocation",
         "divisionID", "racemeetEventInstanceID"]),
    ("race_lane_instances.csv",         "RaceLaneInstance",
        ["raceLaneInstanceID", "timeTakenToCompleteRace",
         "raceInstanceID", "laneTypeID", "swimmerID", "resultTypeID"]),
    ("official_racemeet_roles.csv",     "OfficialRacemeetRoleInstance",
        ["officialID", "racemeetInstanceID", "roleTypeID"]),
    ("nomination_instances.csv",        "NominationInstance",
        ["nominationInstanceID", "dateNominated",
         "racemeetEventInstanceID", "swimmerID"]),
]


def load_csv(conn, csv_path, table, columns):
    """Stream a CSV into the given table. Empty strings become NULL."""
    placeholders = ",".join(["?"] * len(columns))
    sql = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({placeholders})"
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = [
            tuple((r[c] if r[c] != "" else None) for c in columns)
            for r in reader
        ]
    conn.executemany(sql, rows)
    print(f"  loaded {table:35s} {len(rows):>4} rows")


def run_script(conn, path):
    """Execute a .sql file as a single script."""
    with open(path, encoding="utf-8") as f:
        conn.executescript(f.read())


def main():
    if DB_PATH.exists():
        DB_PATH.unlink()
        print(f"Removed existing {DB_PATH.name}")

    conn = sqlite3.connect(DB_PATH)
    # FK enforcement is per-connection in SQLite
    conn.execute("PRAGMA foreign_keys = ON;")

    print("Creating schema...")
    run_script(conn, SQL_DIR / "01_schema.sql")

    print("Loading CSV data:")
    for csv_name, table, cols in LOAD_ORDER:
        load_csv(conn, DATA_DIR / csv_name, table, cols)

    print("Creating indexes...")
    run_script(conn, SQL_DIR / "02_indexes.sql")

    print("Creating views...")
    run_script(conn, SQL_DIR / "10_views.sql")

    # Confirm FKs are still valid (empty result = all good)
    fk_issues = conn.execute("PRAGMA foreign_key_check;").fetchall()
    if fk_issues:
        print(f"\nFOREIGN KEY VIOLATIONS DETECTED: {len(fk_issues)}")
        for row in fk_issues[:5]:
            print(f"  {row}")
        conn.close()
        sys.exit(1)

    conn.commit()
    conn.close()
    size_kb = DB_PATH.stat().st_size / 1024
    print(f"\nBuilt {DB_PATH.name} ({size_kb:.1f} KB). No FK violations.")


if __name__ == "__main__":
    main()
