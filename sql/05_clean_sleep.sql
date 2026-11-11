-- =====================================================================
-- 05.1 Sleep sessions (one row per sleep log)
-- Each session is assigned to the date it ends (wake-up date), which
-- reproduces Fitbit's sleepDay file (log row 9). Sessions present in
-- both export periods are kept once.
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.sleep_sessions AS

WITH minute_sleep AS (
  SELECT DISTINCT 1 AS period, Id AS user_id, logId AS log_id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date) AS minute_ts,
         value
  FROM fitbit_raw.p1_minute_sleep
  UNION ALL
  SELECT DISTINCT 2, Id, logId,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date),
         value
  FROM fitbit_raw.p2_minute_sleep
),

sessions AS (
  SELECT
    period,
    user_id,
    log_id,
    MIN(minute_ts)       AS sleep_start,
    MAX(minute_ts)       AS sleep_end,
    COUNT(*)             AS minutes_in_bed,
    COUNTIF(value = 1)   AS minutes_asleep,
    COUNTIF(value = 2)   AS minutes_restless,
    COUNTIF(value = 3)   AS minutes_awake
  FROM minute_sleep
  GROUP BY period, user_id, log_id
),

deduplicated AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY log_id ORDER BY period DESC) AS period_rank
  FROM sessions
),

dated AS (
  SELECT
    * EXCEPT (period_rank),
    DATE(sleep_end) AS sleep_date
  FROM deduplicated
  WHERE period_rank = 1
)

SELECT
  *,
  ROW_NUMBER() OVER (
    PARTITION BY user_id, sleep_date
    ORDER BY minutes_in_bed DESC, sleep_start
  ) = 1 AS is_main_sleep
FROM dated;

-- =====================================================================
-- 05.2 Nightly sleep (one row per user and wake-up date)
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.sleep_daily AS
SELECT
  user_id,
  sleep_date,
  IF(sleep_date >= DATE '2016-04-12', 2, 1)      AS period,
  COUNT(*)                                       AS sleep_sessions,
  SUM(minutes_asleep)                            AS total_minutes_asleep,
  SUM(minutes_in_bed)                            AS total_minutes_in_bed,
  ROUND(SUM(minutes_asleep) / SUM(minutes_in_bed), 3) AS sleep_efficiency,
  MAX(IF(is_main_sleep, sleep_start, NULL))      AS main_sleep_start,
  MAX(IF(is_main_sleep, sleep_end, NULL))        AS main_sleep_end,
  MAX(IF(is_main_sleep, minutes_asleep, NULL))   AS main_sleep_minutes_asleep
FROM fitbit_clean.sleep_sessions
GROUP BY user_id, sleep_date;

-- 05.3 Sleep sessions checks
-- Expected: 1,007 sessions, 25 users, 0 duplicate log_ids,
-- 832 main sleeps, 175 additional sessions
SELECT
  COUNT(*)                                AS sessions,
  COUNT(DISTINCT user_id)                 AS users,
  COUNT(*) - COUNT(DISTINCT log_id)       AS duplicate_log_ids,
  COUNTIF(is_main_sleep)                  AS main_sleeps,
  COUNTIF(NOT is_main_sleep)              AS additional_sessions
FROM fitbit_clean.sleep_sessions;
-- 05.4 Nightly sleep checks
-- Expected: period 1: 422 nights, period 2: 410 nights; 832 in total,
-- 25 users, dates 2016-03-12 to 2016-05-12
SELECT
  period,
  COUNT(*)                AS nights,
  COUNT(DISTINCT user_id) AS users,
  MIN(sleep_date)         AS first_date,
  MAX(sleep_date)         AS last_date
FROM fitbit_clean.sleep_daily
GROUP BY period
ORDER BY period;
-- 05.5 Validate nightly sleep against Fitbit's sleepDay file (period 2)
-- Expected: 410 nights compared; sessions and time in bed exact in 410;
-- minutes asleep exact in 396, within 5 min in 404;
-- average minutes asleep 419.2 (official) vs 419.4 (rebuilt)
WITH official AS (
  SELECT DISTINCT
    Id AS user_id,
    DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', SleepDay)) AS sleep_date,
    TotalSleepRecords,
    TotalMinutesAsleep,
    TotalTimeInBed
  FROM fitbit_raw.p2_sleep_day
)
SELECT
  COUNT(*)                                                         AS compared_nights,
  COUNTIF(o.TotalSleepRecords = d.sleep_sessions)                  AS sessions_exact,
  COUNTIF(o.TotalTimeInBed = d.total_minutes_in_bed)               AS in_bed_exact,
  COUNTIF(o.TotalMinutesAsleep = d.total_minutes_asleep)           AS asleep_exact,
  COUNTIF(ABS(o.TotalMinutesAsleep - d.total_minutes_asleep) <= 5) AS asleep_within_5min,
  ROUND(AVG(o.TotalMinutesAsleep), 1)                              AS avg_asleep_official,
  ROUND(AVG(d.total_minutes_asleep), 1)                            AS avg_asleep_rebuilt
FROM official AS o
JOIN fitbit_clean.sleep_daily AS d
  USING (user_id, sleep_date);