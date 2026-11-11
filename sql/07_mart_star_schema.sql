-- =====================================================================
-- 07.1 dim_date: one row per calendar day in the study
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_mart.dim_date AS
SELECT
  d                                            AS date,
  EXTRACT(YEAR FROM d)                         AS year,
  EXTRACT(MONTH FROM d)                        AS month,
  FORMAT_DATE('%B', d)                         AS month_name,
  CAST(FORMAT_DATE('%u', d) AS INT64)          AS day_of_week,
  FORMAT_DATE('%A', d)                         AS day_name,
  CAST(FORMAT_DATE('%u', d) AS INT64) >= 6     AS is_weekend,
  DATE_DIFF(d, DATE '2016-03-12', DAY) + 1     AS study_day,
  DIV(DATE_DIFF(d, DATE '2016-03-12', DAY), 7) + 1 AS study_week,
  IF(d >= DATE '2016-04-12', 2, 1)             AS period
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2016-03-12', DATE '2016-05-12')) AS d;

-- =====================================================================
-- 07.2 dim_hour: one row per hour of the day
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_mart.dim_hour AS
SELECT
  h                          AS hour_of_day,
  FORMAT('%02d:00', h)       AS hour_label,
  CASE
    WHEN h BETWEEN 0  AND 5  THEN 'Night'
    WHEN h BETWEEN 6  AND 11 THEN 'Morning'
    WHEN h BETWEEN 12 AND 17 THEN 'Afternoon'
    ELSE 'Evening'
  END                        AS day_part,
  CASE
    WHEN h BETWEEN 0  AND 5  THEN 1
    WHEN h BETWEEN 6  AND 11 THEN 2
    WHEN h BETWEEN 12 AND 17 THEN 3
    ELSE 4
  END                        AS day_part_order
FROM UNNEST(GENERATE_ARRAY(0, 23)) AS h;

-- =====================================================================
-- 07.3 dim_user: one row per user, with activity segment
-- Segments follow step-count categories by Tudor-Locke & Bassett (2004),
-- based on average steps on valid days.
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_mart.dim_user AS

WITH steps AS (
  SELECT user_id, ROUND(AVG(total_steps)) AS avg_daily_steps
  FROM fitbit_clean.daily_activity
  WHERE is_valid_day
  GROUP BY user_id
)

SELECT
  u.*,
  ROUND(u.valid_days / u.days_in_data, 3) AS valid_day_share,
  s.avg_daily_steps,
  CASE
    WHEN s.avg_daily_steps < 5000  THEN 'Sedentary'
    WHEN s.avg_daily_steps < 7500  THEN 'Low active'
    WHEN s.avg_daily_steps < 10000 THEN 'Somewhat active'
    ELSE 'Active'
  END AS activity_segment,
  CASE
    WHEN s.avg_daily_steps < 5000  THEN 1
    WHEN s.avg_daily_steps < 7500  THEN 2
    WHEN s.avg_daily_steps < 10000 THEN 3
    ELSE 4
  END AS activity_segment_order
FROM fitbit_clean.users AS u
LEFT JOIN steps AS s ON u.user_id = s.user_id;

-- =====================================================================
-- 07.4 Fact views (no data copied; they read from fitbit_clean)
-- =====================================================================
CREATE OR REPLACE VIEW fitbit_mart.fact_daily_activity AS
SELECT
  user_id, activity_date, period, data_source,
  total_steps, calories,
  very_active_minutes, fairly_active_minutes, lightly_active_minutes,
  sedentary_minutes, active_minutes, tracked_minutes, recorded_minutes,
  very_active_minutes + fairly_active_minutes AS mvpa_minutes,
  is_zero_step_day, is_partial_day, is_valid_day
FROM fitbit_clean.daily_activity;

CREATE OR REPLACE VIEW fitbit_mart.fact_hourly_activity AS
SELECT
  user_id, activity_date, hour_of_day, hour_start, period,
  steps, calories, active_minutes, mvpa_minutes, is_valid_day
FROM fitbit_clean.hourly_activity;

CREATE OR REPLACE VIEW fitbit_mart.fact_sleep AS
SELECT
  user_id, sleep_date, period, sleep_sessions,
  total_minutes_asleep, total_minutes_in_bed, sleep_efficiency,
  main_sleep_start, main_sleep_end, main_sleep_minutes_asleep,
  EXTRACT(HOUR FROM main_sleep_start) AS main_sleep_start_hour
FROM fitbit_clean.sleep_daily;

CREATE OR REPLACE VIEW fitbit_mart.fact_heart_rate_daily AS
SELECT user_id, activity_date, readings, minutes_with_hr,
       avg_bpm, min_bpm, max_bpm
FROM fitbit_clean.heart_rate_daily;

CREATE OR REPLACE VIEW fitbit_mart.fact_weight_log AS
SELECT user_id, log_date, logged_at, weight_kg, bmi, fat_pct, is_manual_report
FROM fitbit_clean.weight_log;

-- 07.5 Row counts
-- Expected: dim_date 62, dim_hour 24, dim_user 35, fact_daily_activity 1,966,
-- fact_hourly_activity 46,008, fact_sleep 832, fact_heart_rate_daily 469,
-- fact_weight_log 98
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM fitbit_mart.dim_date
UNION ALL SELECT 'dim_hour', COUNT(*) FROM fitbit_mart.dim_hour
UNION ALL SELECT 'dim_user', COUNT(*) FROM fitbit_mart.dim_user
UNION ALL SELECT 'fact_daily_activity', COUNT(*) FROM fitbit_mart.fact_daily_activity
UNION ALL SELECT 'fact_hourly_activity', COUNT(*) FROM fitbit_mart.fact_hourly_activity
UNION ALL SELECT 'fact_sleep', COUNT(*) FROM fitbit_mart.fact_sleep
UNION ALL SELECT 'fact_heart_rate_daily', COUNT(*) FROM fitbit_mart.fact_heart_rate_daily
UNION ALL SELECT 'fact_weight_log', COUNT(*) FROM fitbit_mart.fact_weight_log;

-- 07.6 Referential integrity: every fact row must match a dimension row
-- Expected: 0 in every column
SELECT
  (SELECT COUNT(*) FROM fitbit_mart.fact_daily_activity AS f
   LEFT JOIN fitbit_mart.dim_user AS u ON f.user_id = u.user_id
   WHERE u.user_id IS NULL)                                   AS daily_missing_user,
  (SELECT COUNT(*) FROM fitbit_mart.fact_daily_activity AS f
   LEFT JOIN fitbit_mart.dim_date AS d ON f.activity_date = d.date
   WHERE d.date IS NULL)                                      AS daily_missing_date,
  (SELECT COUNT(*) FROM fitbit_mart.fact_hourly_activity AS f
   LEFT JOIN fitbit_mart.dim_hour AS h ON f.hour_of_day = h.hour_of_day
   WHERE h.hour_of_day IS NULL)                               AS hourly_missing_hour,
  (SELECT COUNT(*) FROM fitbit_mart.fact_sleep AS f
   LEFT JOIN fitbit_mart.dim_date AS d ON f.sleep_date = d.date
   WHERE d.date IS NULL)                                      AS sleep_missing_date,
  (SELECT COUNT(*) FROM fitbit_mart.fact_sleep AS f
   LEFT JOIN fitbit_mart.dim_user AS u ON f.user_id = u.user_id
   WHERE u.user_id IS NULL)                                   AS sleep_missing_user,
  (SELECT COUNT(*) FROM fitbit_mart.fact_weight_log AS f
   LEFT JOIN fitbit_mart.dim_date AS d ON f.log_date = d.date
   WHERE d.date IS NULL)                                      AS weight_missing_date;

-- 07.7 Activity segments
-- Expected: Sedentary 9, Low active 8, Somewhat active 9, Active 9
SELECT activity_segment, COUNT(*) AS users,
       MIN(avg_daily_steps) AS min_steps, MAX(avg_daily_steps) AS max_steps
FROM fitbit_mart.dim_user
GROUP BY activity_segment, activity_segment_order
ORDER BY activity_segment_order;