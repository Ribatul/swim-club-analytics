-- =============================================================================
-- 01_schema.sql  -  Scarborough Summer Swimming Series
-- SQLite DDL for the swim-club analytics database.
-- =============================================================================
-- Design notes:
--   * Identifier style: camelCase short-form for primary keys. The 'Instance'
--     suffix on event tables distinguishes a specific occurrence from the
--     abstract type (RaceInstance vs EventType, etc.).
--   * Dates stored as ISO 8601 TEXT (SQLite convention).
--   * Race times stored as REAL (seconds).
--   * Foreign keys are enforced at runtime via `PRAGMA foreign_keys = ON;`
--     (SQLite requires this per-connection - the load script sets it).
--
-- Schema design choices documented here:
--   * No reserved keywords used as column names (e.g. RacemeetInstance uses
--     racemeetDate, not date).
--   * NOT NULL declared on column definitions (portable, ANSI-standard).
--   * CHECK constraints on every enum-like column (gender, activeStatus,
--     strokeType, individualOrMedley, etc.) so bad data fails at insert.
--   * Composite UNIQUE constraints encode business rules:
--     - A swimmer can't be in two lanes of the same race
--     - Two swimmers can't share a lane in the same race
--     - A swimmer can't nominate twice for the same event
--   * RaceLaneInstance.swimmerID and resultTypeID are NULLABLE so empty
--     lanes (races with fewer than 8 swimmers) can be represented honestly.
-- =============================================================================

-- Drop in reverse dependency order so the script is idempotent.
DROP TABLE IF EXISTS RaceLaneInstance;
DROP TABLE IF EXISTS NominationInstance;
DROP TABLE IF EXISTS OfficialRacemeetRoleInstance;
DROP TABLE IF EXISTS RaceInstance;
DROP TABLE IF EXISTS RacemeetEventInstance;
DROP TABLE IF EXISTS Swimmer;
DROP TABLE IF EXISTS Division;
DROP TABLE IF EXISTS ResultType;
DROP TABLE IF EXISTS LaneType;
DROP TABLE IF EXISTS EventType;
DROP TABLE IF EXISTS RacemeetInstance;
DROP TABLE IF EXISTS RoleType;
DROP TABLE IF EXISTS Coach;
DROP TABLE IF EXISTS Official;

-- -----------------------------------------------------------------------------
-- Reference / lookup tables (no FKs)
-- -----------------------------------------------------------------------------

CREATE TABLE Official (
    officialID         TEXT    PRIMARY KEY,
    firstName          TEXT    NOT NULL,
    lastName           TEXT    NOT NULL,
    employeeStartDate  TEXT    NOT NULL,
    activeStatus       TEXT    NOT NULL CHECK (activeStatus IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE Coach (
    coachID            TEXT    PRIMARY KEY,
    firstName          TEXT    NOT NULL,
    lastName           TEXT    NOT NULL,
    employeeStartDate  TEXT    NOT NULL
);

CREATE TABLE RoleType (
    roleTypeID         TEXT    PRIMARY KEY,
    roleTitle          TEXT    NOT NULL,
    roleDescription    TEXT,
    numberRequired     INTEGER NOT NULL CHECK (numberRequired > 0)
);

CREATE TABLE RacemeetInstance (
    racemeetInstanceID TEXT    PRIMARY KEY,
    weekOfCompetition  INTEGER NOT NULL CHECK (weekOfCompetition BETWEEN 1 AND 52),
    racemeetDate       TEXT    NOT NULL,
    startTime          TEXT    NOT NULL
);

CREATE TABLE EventType (
    eventTypeID        TEXT    PRIMARY KEY,
    eventDescription   TEXT    NOT NULL,
    strokeType         TEXT    NOT NULL CHECK (strokeType IN
                           ('freestyle','breaststroke','butterfly','backstroke','medley')),
    distancePerLeg     INTEGER NOT NULL CHECK (distancePerLeg > 0),
    numberOfLegs       INTEGER NOT NULL CHECK (numberOfLegs > 0),
    individualOrMedley TEXT    NOT NULL CHECK (individualOrMedley IN ('individual','medley'))
);

CREATE TABLE LaneType (
    laneTypeID         TEXT    PRIMARY KEY,
    laneNumber         INTEGER NOT NULL UNIQUE CHECK (laneNumber BETWEEN 1 AND 8)
);

CREATE TABLE ResultType (
    resultTypeID       TEXT    PRIMARY KEY,
    positionResult     TEXT    NOT NULL,
    points             INTEGER NOT NULL CHECK (points >= 0)
);

-- -----------------------------------------------------------------------------
-- Core entities
-- -----------------------------------------------------------------------------

CREATE TABLE Division (
    divisionID         TEXT    PRIMARY KEY,
    age                INTEGER NOT NULL CHECK (age BETWEEN 5 AND 20),
    gender             TEXT    NOT NULL CHECK (gender IN ('M','F')),
    coachID            TEXT    NOT NULL,
    FOREIGN KEY (coachID) REFERENCES Coach(coachID)
);

CREATE TABLE Swimmer (
    swimmerID          TEXT    PRIMARY KEY,
    firstName          TEXT    NOT NULL,
    lastName           TEXT    NOT NULL,
    dob                TEXT    NOT NULL,
    age                INTEGER NOT NULL CHECK (age BETWEEN 5 AND 20),
    gender             TEXT    NOT NULL CHECK (gender IN ('M','F')),
    divisionID         TEXT    NOT NULL,
    FOREIGN KEY (divisionID) REFERENCES Division(divisionID)
);

CREATE TABLE RacemeetEventInstance (
    racemeetEventInstanceID TEXT PRIMARY KEY,
    startTime               TEXT NOT NULL,
    racemeetInstanceID      TEXT NOT NULL,
    eventTypeID             TEXT NOT NULL,
    FOREIGN KEY (racemeetInstanceID) REFERENCES RacemeetInstance(racemeetInstanceID),
    FOREIGN KEY (eventTypeID)        REFERENCES EventType(eventTypeID)
);

CREATE TABLE RaceInstance (
    raceInstanceID          TEXT PRIMARY KEY,
    startTime               TEXT NOT NULL,
    poolLocation            TEXT NOT NULL,
    divisionID              TEXT NOT NULL,
    racemeetEventInstanceID TEXT NOT NULL,
    FOREIGN KEY (divisionID)              REFERENCES Division(divisionID),
    FOREIGN KEY (racemeetEventInstanceID) REFERENCES RacemeetEventInstance(racemeetEventInstanceID)
);

-- -----------------------------------------------------------------------------
-- Transactional / event tables
-- -----------------------------------------------------------------------------

-- RaceLaneInstance: one row per lane per race. swimmerID and resultTypeID are
-- NULLABLE because a race with fewer than 8 swimmers leaves empty lanes.
CREATE TABLE RaceLaneInstance (
    raceLaneInstanceID      TEXT PRIMARY KEY,
    timeTakenToCompleteRace REAL,                 -- NULL for DNS/DNF/DSQ or empty lane
    raceInstanceID          TEXT NOT NULL,
    laneTypeID              TEXT NOT NULL,
    swimmerID               TEXT,                 -- NULL = empty lane
    resultTypeID            TEXT,                 -- NULL = empty lane
    FOREIGN KEY (raceInstanceID) REFERENCES RaceInstance(raceInstanceID),
    FOREIGN KEY (laneTypeID)     REFERENCES LaneType(laneTypeID),
    FOREIGN KEY (swimmerID)      REFERENCES Swimmer(swimmerID),
    FOREIGN KEY (resultTypeID)   REFERENCES ResultType(resultTypeID),
    -- Business rule: a swimmer can't be in two lanes of the same race
    UNIQUE (raceInstanceID, swimmerID),
    -- Business rule: two swimmers can't share a lane in the same race
    UNIQUE (raceInstanceID, laneTypeID)
);

-- Composite-key bridge between Official, RacemeetInstance, and RoleType
CREATE TABLE OfficialRacemeetRoleInstance (
    officialID              TEXT NOT NULL,
    racemeetInstanceID      TEXT NOT NULL,
    roleTypeID              TEXT NOT NULL,
    PRIMARY KEY (officialID, racemeetInstanceID),
    FOREIGN KEY (officialID)         REFERENCES Official(officialID),
    FOREIGN KEY (racemeetInstanceID) REFERENCES RacemeetInstance(racemeetInstanceID),
    FOREIGN KEY (roleTypeID)         REFERENCES RoleType(roleTypeID)
);

-- NominationInstance captures pre-race event sign-ups (which swimmers
-- intend to compete in which events). The composite UNIQUE rule enforces
-- one nomination per swimmer per event.
CREATE TABLE NominationInstance (
    nominationInstanceID    TEXT PRIMARY KEY,
    dateNominated           TEXT NOT NULL,
    racemeetEventInstanceID TEXT NOT NULL,
    swimmerID               TEXT NOT NULL,
    FOREIGN KEY (racemeetEventInstanceID) REFERENCES RacemeetEventInstance(racemeetEventInstanceID),
    FOREIGN KEY (swimmerID)               REFERENCES Swimmer(swimmerID),
    -- A swimmer may only nominate for a given event once
    UNIQUE (swimmerID, racemeetEventInstanceID)
);
