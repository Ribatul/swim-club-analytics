-- =============================================================================
-- 10_views.sql  -  Reusable views for analytics and Power BI
-- =============================================================================
-- These views are the semantic layer between the normalised schema and
-- the dashboard. Power BI connects to these (via ODBC) rather than to the
-- raw tables - so a schema change doesn't break the dashboard, it just
-- requires updating the view.
--
-- Design notes:
--   * v_race_results is a flat fact table (one row per race-lane with every
--     dimension joined). Power BI can model it as a star-schema fact.
--   * All other views aggregate from v_race_results - single source of truth.
--   * NULL swimmerID rows (empty lanes + duplicates we nulled) are filtered
--     out where they'd distort counts; preserved where utilisation matters.
-- =============================================================================

DROP VIEW IF EXISTS v_nomination_audit;
DROP VIEW IF EXISTS v_coach_scorecard;
DROP VIEW IF EXISTS v_weekly_trends;
DROP VIEW IF EXISTS v_season_points;
DROP VIEW IF EXISTS v_swimmer_dim;
DROP VIEW IF EXISTS v_race_results;

-- -----------------------------------------------------------------------------
-- v_race_results : flat fact table, one row per race-lane
-- -----------------------------------------------------------------------------
-- Every dimension unpacked so Power BI / ad-hoc SQL needs no joins.
-- Excludes empty lanes (NULL swimmerID) because they distort per-swimmer counts.
-- Kept: completed, DNS, DNF, DSQ rows (anything where a swimmer was entered).
-- -----------------------------------------------------------------------------
CREATE VIEW v_race_results AS
SELECT
    rli.raceLaneInstanceID,
    rli.timeTakenToCompleteRace        AS time_seconds,
    lt.laneNumber                      AS lane_number,
    -- Swimmer
    s.swimmerID,
    s.firstName || ' ' || s.lastName   AS swimmer_name,
    s.age                              AS swimmer_age,
    s.gender                           AS swimmer_gender,
    -- Division + Coach
    d.divisionID,
    d.age || CASE d.gender WHEN 'M' THEN 'M' ELSE 'F' END AS division_label,
    c.coachID,
    c.firstName || ' ' || c.lastName   AS coach_name,
    -- Race / event
    ri.raceInstanceID,
    ri.poolLocation,
    ri.startTime                       AS race_start_time,
    et.eventTypeID,
    et.strokeType,
    et.eventDescription,
    et.distancePerLeg * et.numberOfLegs AS total_distance_m,
    -- Racemeet
    rmi.racemeetInstanceID,
    rmi.weekOfCompetition              AS week,
    rmi.racemeetDate,
    -- Result
    rt.resultTypeID,
    rt.positionResult,
    rt.points,
    CASE
        WHEN rt.positionResult IN ('DNS','DNF','DSQ') THEN 0
        ELSE 1
    END                                AS completed_flag
FROM RaceLaneInstance    rli
JOIN LaneType            lt   ON rli.laneTypeID      = lt.laneTypeID
JOIN RaceInstance        ri   ON rli.raceInstanceID  = ri.raceInstanceID
JOIN RacemeetEventInstance rmei ON ri.racemeetEventInstanceID = rmei.racemeetEventInstanceID
JOIN RacemeetInstance    rmi  ON rmei.racemeetInstanceID = rmi.racemeetInstanceID
JOIN EventType           et   ON rmei.eventTypeID   = et.eventTypeID
JOIN Division            d    ON ri.divisionID      = d.divisionID
JOIN Coach               c    ON d.coachID          = c.coachID
JOIN Swimmer             s    ON rli.swimmerID      = s.swimmerID
LEFT JOIN ResultType     rt   ON rli.resultTypeID   = rt.resultTypeID;

-- -----------------------------------------------------------------------------
-- v_swimmer_dim : clean swimmer dimension for Power BI
-- -----------------------------------------------------------------------------
CREATE VIEW v_swimmer_dim AS
SELECT
    s.swimmerID,
    s.firstName,
    s.lastName,
    s.firstName || ' ' || s.lastName AS swimmer_name,
    s.dob,
    s.age,
    s.gender,
    d.divisionID,
    d.age || CASE d.gender WHEN 'M' THEN 'M' ELSE 'F' END AS division_label,
    c.coachID,
    c.firstName || ' ' || c.lastName AS coach_name
FROM Swimmer   s
JOIN Division  d ON s.divisionID = d.divisionID
JOIN Coach     c ON d.coachID    = c.coachID;

-- -----------------------------------------------------------------------------
-- v_season_points : per-swimmer season totals
-- -----------------------------------------------------------------------------
-- Powers the division-leaderboard page of the dashboard.
-- LEFT JOIN preserves swimmers who never scored (or never raced).
-- -----------------------------------------------------------------------------
CREATE VIEW v_season_points AS
SELECT
    sd.swimmerID,
    sd.swimmer_name,
    sd.divisionID,
    sd.division_label,
    sd.coach_name,
    COUNT(rr.raceLaneInstanceID)                    AS races_entered,
    SUM(rr.completed_flag)                          AS races_completed,
    COALESCE(SUM(rr.points), 0)                     AS total_points,
    SUM(CASE WHEN rr.positionResult = '1st' THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN rr.positionResult IN ('DNF','DSQ') THEN 1 ELSE 0 END) AS dnf_dsq
FROM v_swimmer_dim sd
LEFT JOIN v_race_results rr ON sd.swimmerID = rr.swimmerID
GROUP BY sd.swimmerID, sd.swimmer_name, sd.divisionID, sd.division_label, sd.coach_name;

-- -----------------------------------------------------------------------------
-- v_weekly_trends : swimmer times per stroke per week
-- -----------------------------------------------------------------------------
-- Powers the swimmer-performance-over-time page of the dashboard.
-- Only completed swims (NULL times filtered out).
-- -----------------------------------------------------------------------------
CREATE VIEW v_weekly_trends AS
SELECT
    swimmerID,
    swimmer_name,
    divisionID,
    division_label,
    strokeType,
    eventDescription,
    week,
    racemeetDate,
    time_seconds,
    positionResult,
    points
FROM v_race_results
WHERE completed_flag = 1
  AND time_seconds IS NOT NULL;

-- -----------------------------------------------------------------------------
-- v_coach_scorecard : coach-level KPIs
-- -----------------------------------------------------------------------------
-- Powers the coach-effectiveness page. Normalises by swimmer count so
-- coaches with different-sized divisions are comparable.
-- -----------------------------------------------------------------------------
CREATE VIEW v_coach_scorecard AS
SELECT
    coach_name,
    divisionID,
    division_label,
    COUNT(DISTINCT swimmerID)                       AS swimmer_count,
    COUNT(raceLaneInstanceID)                       AS races_entered,
    SUM(completed_flag)                             AS races_completed,
    SUM(points)                                     AS total_points,
    ROUND(1.0 * SUM(points) / COUNT(DISTINCT swimmerID), 2) AS points_per_swimmer,
    SUM(CASE WHEN positionResult = '1st' THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN positionResult IN ('DNF','DSQ') THEN 1 ELSE 0 END) AS dnf_dsq,
    ROUND(100.0 * SUM(CASE WHEN positionResult IN ('DNF','DSQ') THEN 1 ELSE 0 END)
                / COUNT(raceLaneInstanceID), 2)     AS dnf_dsq_rate_pct
FROM v_race_results
GROUP BY coach_name, divisionID, division_label;

-- -----------------------------------------------------------------------------
-- v_nomination_audit : nomination vs actual participation
-- -----------------------------------------------------------------------------
-- Powers the data-quality page of the dashboard.
-- FULL OUTER JOIN equivalent via UNION (SQLite lacks FULL OUTER).
-- Each row is one (swimmer, event) pair with status.
-- -----------------------------------------------------------------------------
CREATE VIEW v_nomination_audit AS
-- Nominated and raced
SELECT
    n.swimmerID,
    sd.swimmer_name,
    sd.division_label,
    n.racemeetEventInstanceID,
    et.eventDescription,
    rmi.weekOfCompetition AS week,
    'Nominated and raced' AS status
FROM NominationInstance n
JOIN v_swimmer_dim sd ON n.swimmerID = sd.swimmerID
JOIN RacemeetEventInstance rmei ON n.racemeetEventInstanceID = rmei.racemeetEventInstanceID
JOIN EventType et ON rmei.eventTypeID = et.eventTypeID
JOIN RacemeetInstance rmi ON rmei.racemeetInstanceID = rmi.racemeetInstanceID
WHERE EXISTS (
    SELECT 1 FROM RaceLaneInstance rli
    JOIN RaceInstance ri ON rli.raceInstanceID = ri.raceInstanceID
    WHERE rli.swimmerID = n.swimmerID
      AND ri.racemeetEventInstanceID = n.racemeetEventInstanceID
)
UNION ALL
-- Nominated but DID NOT race
SELECT
    n.swimmerID,
    sd.swimmer_name,
    sd.division_label,
    n.racemeetEventInstanceID,
    et.eventDescription,
    rmi.weekOfCompetition AS week,
    'Nominated but did not race' AS status
FROM NominationInstance n
JOIN v_swimmer_dim sd ON n.swimmerID = sd.swimmerID
JOIN RacemeetEventInstance rmei ON n.racemeetEventInstanceID = rmei.racemeetEventInstanceID
JOIN EventType et ON rmei.eventTypeID = et.eventTypeID
JOIN RacemeetInstance rmi ON rmei.racemeetInstanceID = rmi.racemeetInstanceID
WHERE NOT EXISTS (
    SELECT 1 FROM RaceLaneInstance rli
    JOIN RaceInstance ri ON rli.raceInstanceID = ri.raceInstanceID
    WHERE rli.swimmerID = n.swimmerID
      AND ri.racemeetEventInstanceID = n.racemeetEventInstanceID
)
UNION ALL
-- Raced but DID NOT nominate
SELECT DISTINCT
    rli.swimmerID,
    sd.swimmer_name,
    sd.division_label,
    ri.racemeetEventInstanceID,
    et.eventDescription,
    rmi.weekOfCompetition AS week,
    'Raced but did not nominate' AS status
FROM RaceLaneInstance rli
JOIN v_swimmer_dim sd ON rli.swimmerID = sd.swimmerID
JOIN RaceInstance ri ON rli.raceInstanceID = ri.raceInstanceID
JOIN RacemeetEventInstance rmei ON ri.racemeetEventInstanceID = rmei.racemeetEventInstanceID
JOIN EventType et ON rmei.eventTypeID = et.eventTypeID
JOIN RacemeetInstance rmi ON rmei.racemeetInstanceID = rmi.racemeetInstanceID
WHERE rli.swimmerID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM NominationInstance n
      WHERE n.swimmerID = rli.swimmerID
        AND n.racemeetEventInstanceID = ri.racemeetEventInstanceID
  );
