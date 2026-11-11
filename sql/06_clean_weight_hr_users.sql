-- =====================================================================
-- 06.1 Weight log
-- Key is (user_id, log_id): LogId is a millisecond timestamp and repeats
-- across users who log at the same time (e.g. 23:59:59 manual entries).
-- Two entries from 2016-04-12 appear in both periods; kept once.
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.weight_log AS

WITH combined AS (
  SELECT 1 AS period, Id AS user_id, LogId AS log_id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date) AS logged_at,
         WeightKg AS weight_kg, BMI AS bmi, Fat AS fat_pct,
         IsManualReport AS is_manual_report
  FROM fitbit_raw.p1_weight_log
  UNION ALL
  SELECT 2, Id, LogId,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date),
         WeightKg, BMI, Fat, IsManualReport
  FROM fitbit_raw.p2_weight_log
),

ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY user_id, log_id ORDER BY period DESC) AS rn
  FROM combined
)

SELECT * EXCEPT (rn), DATE(logged_at) AS log_date
FROM ranked
WHERE rn = 1;

-- =====================================================================
-- 06.2 Daily heart-rate summary
-- Readings from 2016-04-12 appear in both periods with identical values;
-- UNION DISTINCT keeps one copy. minutes_with_hr measures actual wear time
-- (heart rate is recorded only while the device touches the skin).
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.heart_rate_daily AS

WITH readings AS (
  SELECT Id AS user_id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time) AS reading_ts,
         Value AS bpm
  FROM fitbit_raw.p1_heartrate_seconds
  UNION DISTINCT
  SELECT Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time),
         Value
  FROM fitbit_raw.p2_heartrate_seconds
)

SELECT
  user_id,
  DATE(reading_ts)                                    AS activity_date,
  COUNT(*)                                            AS readings,
  COUNT(DISTINCT DATETIME_TRUNC(reading_ts, MINUTE))  AS minutes_with_hr,
  ROUND(AVG(bpm), 1)                                  AS avg_bpm,
  MIN(bpm)                                            AS min_bpm,
  MAX(bpm)                                            AS max_bpm
FROM readings
GROUP BY user_id, activity_date;

-- =====================================================================
-- 06.3 Users: one row per user with data coverage and feature use
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.users AS

WITH activity AS (
  SELECT user_id,
         MIN(activity_date)     AS first_activity_date,
         MAX(activity_date)     AS last_activity_date,
         COUNT(*)               AS days_in_data,
         COUNTIF(is_valid_day)  AS valid_days
  FROM fitbit_clean.daily_activity
  GROUP BY user_id
),
sleep AS (
  SELECT user_id, COUNT(*) AS nights_tracked
  FROM fitbit_clean.sleep_daily
  GROUP BY user_id
),
heart_rate AS (
  SELECT user_id, COUNT(*) AS heart_rate_days
  FROM fitbit_clean.heart_rate_daily
  GROUP BY user_id
),
weight AS (
  SELECT user_id,
         COUNT(*)                   AS weight_logs,
         COUNTIF(is_manual_report)  AS manual_weight_logs
  FROM fitbit_clean.weight_log
  GROUP BY user_id
)

SELECT
  a.user_id,
  a.first_activity_date,
  a.last_activity_date,
  a.days_in_data,
  a.valid_days,
  IFNULL(s.nights_tracked, 0)      AS nights_tracked,
  IFNULL(h.heart_rate_days, 0)     AS heart_rate_days,
  IFNULL(w.weight_logs, 0)         AS weight_logs,
  IFNULL(w.manual_weight_logs, 0)  AS manual_weight_logs,
  s.user_id IS NOT NULL            AS uses_sleep_tracking,
  h.user_id IS NOT NULL            AS uses_heart_rate,
  w.user_id IS NOT NULL            AS uses_weight_log
FROM activity AS a
LEFT JOIN sleep      AS s ON a.user_id = s.user_id
LEFT JOIN heart_rate AS h ON a.user_id = h.user_id
LEFT JOIN weight     AS w ON a.user_id = w.user_id;

-- 06.4 Checks
-- Expected: weight_log 98 rows, 13 users, 63 manual entries, 0 duplicate keys;
-- heart_rate_daily 469 rows, 15 users;
-- users 35 rows, 25 sleep, 15 heart rate, 13 weight
SELECT 'weight_log' AS table_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT user_id) AS users,
       COUNTIF(is_manual_report) AS extra_metric,
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%d', user_id, log_id)) AS duplicate_keys
FROM fitbit_clean.weight_log
UNION ALL
SELECT 'heart_rate_daily', COUNT(*), COUNT(DISTINCT user_id),
       SUM(readings),
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%t', user_id, activity_date))
FROM fitbit_clean.heart_rate_daily
UNION ALL
SELECT 'users', COUNT(*), COUNT(DISTINCT user_id),
       COUNTIF(uses_sleep_tracking),
       COUNT(*) - COUNT(DISTINCT user_id)
FROM fitbit_clean.users;

-- 06.5 Feature use summary (should match audit query 7)
-- Expected: 35 users; 25 sleep, 15 heart rate, 13 weight
SELECT
  COUNT(*)                     AS users,
  COUNTIF(uses_sleep_tracking) AS sleep_users,
  COUNTIF(uses_heart_rate)     AS heart_rate_users,
  COUNTIF(uses_weight_log)     AS weight_users,
  SUM(weight_logs)             AS weight_logs,
  SUM(manual_weight_logs)      AS manual_weight_logs
FROM fitbit_clean.users;