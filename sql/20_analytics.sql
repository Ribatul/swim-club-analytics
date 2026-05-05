-- =============================================================================
-- 20_analytics.sql  -  Advanced analytical queries
-- =============================================================================
-- Each query is self-contained. Run any one to see the result. The notebook
-- (notebooks/analytics_showcase.ipynb) pairs each query with narrative and
-- a rendered result table.
--
-- Techniques demonstrated:
--   * Window functions: LAG, LEAD, RANK, DENSE_RANK, ROW_NUMBER, SUM OVER
--   * CTEs (WITH ... AS) for multi-step readability
--   * Conditional aggregates (SUM CASE WHEN ...)
--   * Anti-joins (NOT EXISTS) for gap analysis
--   * Percentage-of-total and share-of-x calculations
-- =============================================================================


-- =============================================================================
-- Q1. Week-on-week improvement per swimmer per stroke (LAG window function)
-- =============================================================================
-- For each swimmer's freestyle times, show how much they improved vs the
-- previous week. Positive = faster this week. Null = first week of competing.
-- This is the foundation of the "swimmer trending" dashboard page.
-- ----------------------------------------------------------------------------
WITH swimmer_times AS (
    SELECT
        swimmer_name,
        division_label,
        week,
        time_seconds,
        LAG(time_seconds) OVER (
            PARTITION BY swimmerID, strokeType
            ORDER BY week
        ) AS prev_week_time
    FROM v_weekly_trends
    WHERE strokeType = 'freestyle'
)
SELECT
    swimmer_name,
    division_label,
    week,
    time_seconds                         AS time_this_week,
    prev_week_time,
    ROUND(prev_week_time - time_seconds, 2) AS improvement_seconds
FROM swimmer_times
WHERE prev_week_time IS NOT NULL
ORDER BY improvement_seconds DESC NULLS LAST
LIMIT 15;


-- =============================================================================
-- Q2. Division leaderboards with proper ranking (DENSE_RANK window function)
-- =============================================================================
-- Ranks every swimmer within their division by season points. Ties get the
-- same rank and the next rank is consecutive (not skipped).
-- Powers the leaderboard page of the dashboard.
-- ----------------------------------------------------------------------------
SELECT
    division_label,
    DENSE_RANK() OVER (
        PARTITION BY divisionID
        ORDER BY total_points DESC, wins DESC
    ) AS division_rank,
    swimmer_name,
    coach_name,
    races_completed,
    total_points,
    wins
FROM v_season_points
WHERE total_points > 0
ORDER BY divisionID, division_rank;


-- =============================================================================
-- Q3. Season best time per stroke per division (ROW_NUMBER window function)
-- =============================================================================
-- Returns the fastest time for every stroke-division combination in a single
-- query. Using ROW_NUMBER() with a partition is far more efficient than
-- separate correlated subqueries per stroke and dramatically less code.
-- ----------------------------------------------------------------------------
WITH ranked_times AS (
    SELECT
        strokeType,
        division_label,
        week,
        swimmer_name,
        time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY strokeType, divisionID
            ORDER BY time_seconds ASC
        ) AS time_rank
    FROM v_weekly_trends
)
SELECT
    strokeType,
    division_label,
    swimmer_name,
    time_seconds AS fastest_time,
    week         AS set_in_week
FROM ranked_times
WHERE time_rank = 1
ORDER BY strokeType, division_label;


-- =============================================================================
-- Q4. Each swimmer's rolling average time (window with unbounded preceding)
-- =============================================================================
-- Running average of a swimmer's freestyle times across the season. Useful
-- for seeing whether a swimmer is consistently improving or volatile.
-- ----------------------------------------------------------------------------
SELECT
    swimmer_name,
    week,
    time_seconds,
    ROUND(AVG(time_seconds) OVER (
        PARTITION BY swimmerID
        ORDER BY week
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS running_avg_seconds,
    COUNT(*) OVER (
        PARTITION BY swimmerID
        ORDER BY week
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS races_so_far
FROM v_weekly_trends
WHERE strokeType = 'freestyle'
ORDER BY swimmer_name, week
LIMIT 20;


-- =============================================================================
-- Q5. Coach effectiveness scorecard (aggregation + ranking)
-- =============================================================================
-- Which coach's division performs best? Four complementary metrics so no
-- single ranking dominates the story.
-- Powers the coach-effectiveness dashboard page.
-- ----------------------------------------------------------------------------
SELECT
    RANK() OVER (ORDER BY points_per_swimmer DESC) AS points_rank,
    coach_name,
    division_label,
    swimmer_count,
    total_points,
    points_per_swimmer,
    wins,
    dnf_dsq_rate_pct
FROM v_coach_scorecard
ORDER BY points_rank;


-- =============================================================================
-- Q6. Nomination reliability - headline metrics (conditional aggregation)
-- =============================================================================
-- One-row summary of the nomination-vs-actual data quality story.
-- Note the 4.27x multiplier in 'raced without nominating' - a clear signal
-- that nomination capture is incomplete.
-- ----------------------------------------------------------------------------
SELECT
    SUM(CASE WHEN status = 'Nominated and raced'           THEN 1 ELSE 0 END) AS nominated_and_raced,
    SUM(CASE WHEN status = 'Nominated but did not race'    THEN 1 ELSE 0 END) AS nominated_no_show,
    SUM(CASE WHEN status = 'Raced but did not nominate'    THEN 1 ELSE 0 END) AS raced_without_nominating,
    ROUND(100.0 * SUM(CASE WHEN status = 'Nominated but did not race' THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN status IN ('Nominated and raced','Nominated but did not race')
                                  THEN 1 ELSE 0 END), 0), 2)
        AS nomination_no_show_rate_pct
FROM v_nomination_audit;


-- =============================================================================
-- Q7. Swimmers who raced every single week (CTE + HAVING)
-- =============================================================================
-- Identifies the most committed swimmers - those who competed in all 4 weeks.
-- The 'reliability' segment that coaches most want to know about.
-- ----------------------------------------------------------------------------
WITH weeks_per_swimmer AS (
    SELECT
        swimmerID,
        swimmer_name,
        division_label,
        COUNT(DISTINCT week) AS weeks_competed
    FROM v_race_results
    GROUP BY swimmerID, swimmer_name, division_label
)
SELECT
    division_label,
    COUNT(*) AS fully_committed_swimmers,
    GROUP_CONCAT(swimmer_name, ', ') AS swimmer_names
FROM weeks_per_swimmer
WHERE weeks_competed = 4
GROUP BY division_label
ORDER BY division_label;


-- =============================================================================
-- Q8. Top performer per division per week (partitioned ranking)
-- =============================================================================
-- Who topped the points per division each week? Shows winners over time
-- and highlights if one swimmer dominates or if it rotates.
-- ----------------------------------------------------------------------------
WITH weekly_points AS (
    SELECT
        divisionID,
        division_label,
        week,
        swimmerID,
        swimmer_name,
        SUM(points) AS weekly_points
    FROM v_race_results
    GROUP BY divisionID, division_label, week, swimmerID, swimmer_name
),
ranked AS (
    SELECT *,
        DENSE_RANK() OVER (PARTITION BY divisionID, week ORDER BY weekly_points DESC) AS rnk
    FROM weekly_points
)
SELECT division_label, week, swimmer_name, weekly_points
FROM ranked
WHERE rnk = 1
ORDER BY division_label, week;


-- =============================================================================
-- Q9. DNF/DSQ anomaly detection (swimmers above expected failure rate)
-- =============================================================================
-- Identifies swimmers whose DNF/DSQ rate exceeds the season average, which
-- for a coach might signal technique issues, injury, or poor race management.
-- ----------------------------------------------------------------------------
WITH swimmer_rates AS (
    SELECT
        swimmerID,
        swimmer_name,
        division_label,
        COUNT(*) AS races,
        SUM(CASE WHEN positionResult IN ('DNF','DSQ') THEN 1 ELSE 0 END) AS dnf_dsq,
        1.0 * SUM(CASE WHEN positionResult IN ('DNF','DSQ') THEN 1 ELSE 0 END) / COUNT(*) AS dnf_rate
    FROM v_race_results
    GROUP BY swimmerID, swimmer_name, division_label
    HAVING COUNT(*) >= 3
),
season_avg AS (
    SELECT 1.0 * SUM(dnf_dsq) / SUM(races) AS avg_dnf_rate
    FROM swimmer_rates
)
SELECT
    swimmer_name,
    division_label,
    races,
    dnf_dsq,
    ROUND(100.0 * dnf_rate, 2)       AS swimmer_dnf_rate_pct,
    ROUND(100.0 * (SELECT avg_dnf_rate FROM season_avg), 2) AS season_avg_pct
FROM swimmer_rates
WHERE dnf_rate > (SELECT avg_dnf_rate FROM season_avg)
ORDER BY dnf_rate DESC;


-- =============================================================================
-- Q10. Lane utilisation (how full are our pools?)
-- =============================================================================
-- For each event type, what percent of available lane slots are used?
-- A club with 8 lanes per race should target >80% utilisation.
-- ----------------------------------------------------------------------------
SELECT
    et.eventDescription,
    et.strokeType,
    COUNT(*)                                        AS total_lane_slots,
    SUM(CASE WHEN rli.swimmerID IS NOT NULL THEN 1 ELSE 0 END) AS lanes_used,
    ROUND(100.0 * SUM(CASE WHEN rli.swimmerID IS NOT NULL THEN 1 ELSE 0 END)
                / COUNT(*), 1)                     AS utilisation_pct
FROM RaceLaneInstance rli
JOIN RaceInstance ri ON rli.raceInstanceID = ri.raceInstanceID
JOIN RacemeetEventInstance rmei ON ri.racemeetEventInstanceID = rmei.racemeetEventInstanceID
JOIN EventType et ON rmei.eventTypeID = et.eventTypeID
GROUP BY et.eventDescription, et.strokeType
ORDER BY utilisation_pct DESC;


-- =============================================================================
-- Q11. Personal best progression (did swimmers peak early or late?)
-- =============================================================================
-- For each swimmer's freestyle, identifies in which week they set their
-- personal best. If most PBs are in week 4, training is working.
-- If most are in week 1, the season peaked too early.
-- ----------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        swimmerID,
        swimmer_name,
        division_label,
        week,
        time_seconds,
        ROW_NUMBER() OVER (PARTITION BY swimmerID ORDER BY time_seconds ASC) AS pb_rank
    FROM v_weekly_trends
    WHERE strokeType = 'freestyle'
)
SELECT
    week AS pb_week,
    COUNT(*) AS swimmers_with_pb_this_week
FROM ranked
WHERE pb_rank = 1
GROUP BY week
ORDER BY week;


-- =============================================================================
-- Q12. Multi-stroke participation tracker
-- =============================================================================
-- Operational question: identify the 13M swimmer who competed in freestyle,
-- butterfly, AND medley in week 2, and list all their results that week.
-- Pattern: HAVING COUNT(DISTINCT...) finds entities that hit a threshold
-- across multiple categories - a useful template for cross-event audit
-- queries (e.g. "find swimmers who entered every stroke type").
-- ----------------------------------------------------------------------------
WITH target_swimmers AS (
    -- 13yo boys who swam all three required strokes in week 2
    SELECT swimmerID
    FROM v_race_results
    WHERE week = 2
      AND swimmer_age = 13
      AND swimmer_gender = 'M'
      AND strokeType IN ('freestyle','butterfly','medley')
    GROUP BY swimmerID
    HAVING COUNT(DISTINCT strokeType) = 3
    LIMIT 1
)
SELECT
    rr.swimmer_name             AS competitor,
    rr.eventDescription,
    rr.race_start_time,
    rr.positionResult           AS result,
    rr.time_seconds,
    rr.points
FROM v_race_results rr
JOIN target_swimmers ts ON rr.swimmerID = ts.swimmerID
WHERE rr.week = 2
ORDER BY rr.race_start_time;
