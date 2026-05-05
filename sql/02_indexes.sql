-- =============================================================================
-- 02_indexes.sql  -  Supporting indexes for the analytical workload
-- =============================================================================
-- PKs are indexed automatically by SQLite. These extra indexes support the
-- joins and filters used heavily in Phase 2 analytics (trending per swimmer,
-- division leaderboards, nomination-vs-actual comparisons, etc.).
-- =============================================================================

-- Swimmer lookups by division (used in leaderboards, coach effectiveness)
CREATE INDEX IF NOT EXISTS idx_swimmer_division
    ON Swimmer (divisionID);

-- RaceInstance filters by racemeet event (used in 'races per week' queries)
CREATE INDEX IF NOT EXISTS idx_race_instance_rmei
    ON RaceInstance (racemeetEventInstanceID);

CREATE INDEX IF NOT EXISTS idx_race_instance_division
    ON RaceInstance (divisionID);

-- RacemeetEventInstance filters (used in 'all events in week N' queries)
CREATE INDEX IF NOT EXISTS idx_rmei_racemeet
    ON RacemeetEventInstance (racemeetInstanceID);

CREATE INDEX IF NOT EXISTS idx_rmei_event
    ON RacemeetEventInstance (eventTypeID);

-- RaceLaneInstance: the analytical hot-spot table
CREATE INDEX IF NOT EXISTS idx_rli_swimmer
    ON RaceLaneInstance (swimmerID);

CREATE INDEX IF NOT EXISTS idx_rli_race
    ON RaceLaneInstance (raceInstanceID);

CREATE INDEX IF NOT EXISTS idx_rli_result
    ON RaceLaneInstance (resultTypeID);

-- Nomination lookups by swimmer (for nomination-vs-actual analysis)
CREATE INDEX IF NOT EXISTS idx_nom_swimmer
    ON NominationInstance (swimmerID);

CREATE INDEX IF NOT EXISTS idx_nom_event
    ON NominationInstance (racemeetEventInstanceID);
