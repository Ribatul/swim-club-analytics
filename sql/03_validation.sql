-- =============================================================================
-- 03_validation.sql  -  Prove the database loaded correctly
-- =============================================================================
-- Run these after load_data.py. All row counts should match the CSV sources,
-- all integrity checks should return 0 rows, and the two expected 'features'
-- (empty lanes, raced-without-nominating) should match the audit numbers.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Row counts per entity (expected vs actual)
-- -----------------------------------------------------------------------------
SELECT 'Official'                        AS entity, COUNT(*) AS rows, 13  AS expected FROM Official UNION ALL
SELECT 'Coach',                                     COUNT(*),        6        FROM Coach UNION ALL
SELECT 'RoleType',                                  COUNT(*),        3        FROM RoleType UNION ALL
SELECT 'RacemeetInstance',                          COUNT(*),        4        FROM RacemeetInstance UNION ALL
SELECT 'EventType',                                 COUNT(*),        5        FROM EventType UNION ALL
SELECT 'LaneType',                                  COUNT(*),        8        FROM LaneType UNION ALL
SELECT 'ResultType',                                COUNT(*),       11        FROM ResultType UNION ALL
SELECT 'Division',                                  COUNT(*),        6        FROM Division UNION ALL
SELECT 'Swimmer',                                   COUNT(*),       85        FROM Swimmer UNION ALL
SELECT 'RacemeetEventInstance',                     COUNT(*),       20        FROM RacemeetEventInstance UNION ALL
SELECT 'RaceInstance',                              COUNT(*),      120        FROM RaceInstance UNION ALL
SELECT 'RaceLaneInstance',                          COUNT(*),      960        FROM RaceLaneInstance UNION ALL
SELECT 'OfficialRacemeetRoleInstance',              COUNT(*),       28        FROM OfficialRacemeetRoleInstance UNION ALL
SELECT 'NominationInstance',                        COUNT(*),      149        FROM NominationInstance;

-- -----------------------------------------------------------------------------
-- 2. Referential integrity spot-checks (all should return 0)
-- -----------------------------------------------------------------------------
-- Swimmer must belong to a valid division
SELECT COUNT(*) AS orphan_swimmers
FROM Swimmer s
LEFT JOIN Division d ON s.divisionID = d.divisionID
WHERE d.divisionID IS NULL;

-- Nomination must reference a valid swimmer (tests the swmr1 -> swmr01 fix)
SELECT COUNT(*) AS orphan_nominations
FROM NominationInstance n
LEFT JOIN Swimmer s ON n.swimmerID = s.swimmerID
WHERE s.swimmerID IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Expected data-quality 'features' (not bugs)
-- -----------------------------------------------------------------------------
-- Empty lanes (races with <8 swimmers). Expected: 184
SELECT COUNT(*) AS empty_lanes
FROM RaceLaneInstance
WHERE swimmerID IS NULL;

-- Swimmers who raced but never nominated. Expected: 15
SELECT COUNT(DISTINCT rli.swimmerID) AS raced_without_nominating
FROM RaceLaneInstance rli
WHERE rli.swimmerID IS NOT NULL
  AND rli.swimmerID NOT IN (SELECT swimmerID FROM NominationInstance);

-- Each swimmer's division matches their age and gender
SELECT COUNT(*) AS swimmer_division_mismatches
FROM Swimmer s
JOIN Division d ON s.divisionID = d.divisionID
WHERE s.age <> d.age OR s.gender <> d.gender;

-- -----------------------------------------------------------------------------
-- 4. Sanity peek at the data
-- -----------------------------------------------------------------------------
-- Divisions with their coach and swimmer count
SELECT d.divisionID,
       d.age,
       d.gender,
       c.firstName || ' ' || c.lastName AS coach,
       COUNT(s.swimmerID)               AS swimmers
FROM Division d
JOIN Coach c    ON d.coachID = c.coachID
LEFT JOIN Swimmer s ON s.divisionID = d.divisionID
GROUP BY d.divisionID, d.age, d.gender, coach
ORDER BY d.age, d.gender;
