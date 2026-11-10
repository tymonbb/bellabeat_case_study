-- =====================================================================
-- 2.1 Rebuild daily activity from minute and hourly data (both periods)
-- Needed because the period 1 daily file is incomplete
-- (see docs/data_quality_log.md, row 2). Period 2 is rebuilt as well,
-- to validate the method against the original daily file (query 2.2).
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.daily_rebuilt AS

WITH minute_intensity AS (
  SELECT 1 AS period, Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute) AS minute_ts,
         Intensity
  FROM fitbit_raw.p1_minute_intensities
  UNION ALL
  SELECT 2, Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute),
         Intensity
  FROM fitbit_raw.p2_minute_intensities
),

intensity_daily AS (
  SELECT
    period,
    Id,
    DATE(minute_ts)          AS activity_date,
    COUNT(*)                 AS recorded_minutes,
    COUNTIF(Intensity = 3)   AS very_active_minutes,
    COUNTIF(Intensity = 2)   AS fairly_active_minutes,
    COUNTIF(Intensity = 1)   AS lightly_active_minutes,
    COUNTIF(Intensity = 0)   AS zero_intensity_minutes
  FROM minute_intensity
  GROUP BY period, Id, activity_date
),

minute_sleep AS (
  SELECT DISTINCT 1 AS period, Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date) AS minute_ts
  FROM fitbit_raw.p1_minute_sleep
  UNION ALL
  SELECT DISTINCT 2, Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date)
  FROM fitbit_raw.p2_minute_sleep
),

sleep_daily AS (
  SELECT period, Id, DATE(minute_ts) AS activity_date,
         COUNT(*) AS sleep_log_minutes
  FROM minute_sleep
  GROUP BY period, Id, activity_date
),

hourly AS (
  SELECT 1 AS period, s.Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', s.ActivityHour)) AS activity_date,
         s.StepTotal, c.Calories
  FROM fitbit_raw.p1_hourly_steps AS s
  JOIN fitbit_raw.p1_hourly_calories AS c
    ON s.Id = c.Id AND s.ActivityHour = c.ActivityHour
  UNION ALL
  SELECT 2, s.Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', s.ActivityHour)),
         s.StepTotal, c.Calories
  FROM fitbit_raw.p2_hourly_steps AS s
  JOIN fitbit_raw.p2_hourly_calories AS c
    ON s.Id = c.Id AND s.ActivityHour = c.ActivityHour
),

hourly_daily AS (
  SELECT period, Id, activity_date,
         SUM(StepTotal) AS total_steps,
         SUM(Calories)  AS calories
  FROM hourly
  GROUP BY period, Id, activity_date
)

SELECT
  i.period,
  i.Id AS user_id,
  i.activity_date,
  h.total_steps,
  h.calories,
  i.very_active_minutes,
  i.fairly_active_minutes,
  i.lightly_active_minutes,
  GREATEST(i.zero_intensity_minutes - IFNULL(s.sleep_log_minutes, 0), 0) AS sedentary_minutes,
  IFNULL(s.sleep_log_minutes, 0) AS sleep_log_minutes,
  i.recorded_minutes
FROM intensity_daily AS i
LEFT JOIN hourly_daily AS h
  ON i.period = h.period AND i.Id = h.Id AND i.activity_date = h.activity_date
LEFT JOIN sleep_daily AS s
  ON i.period = s.period AND i.Id = s.Id AND i.activity_date = s.activity_date;

-- =====================================================================
-- 2.2 Validate the rebuild against the original period 2 daily file
-- =====================================================================
WITH official AS (
  SELECT
    Id                                   AS user_id,
    PARSE_DATE('%m/%d/%Y', ActivityDate) AS activity_date,
    TotalSteps           AS official_steps,
    Calories             AS official_calories,
    VeryActiveMinutes    AS official_very_active,
    FairlyActiveMinutes  AS official_fairly_active,
    LightlyActiveMinutes AS official_lightly_active,
    SedentaryMinutes     AS official_sedentary
  FROM fitbit_raw.p2_daily_activity
),

compared AS (
  SELECT o.*, r.total_steps, r.calories, r.very_active_minutes,
         r.fairly_active_minutes, r.lightly_active_minutes, r.sedentary_minutes
  FROM official AS o
  JOIN fitbit_clean.daily_rebuilt AS r
    ON o.user_id = r.user_id
   AND o.activity_date = r.activity_date
   AND r.period = 2
)

SELECT
  COUNT(*) AS compared_days,
  ROUND(100 * COUNTIF(official_steps = total_steps) / COUNT(*), 1)
    AS steps_exact_pct,
  ROUND(100 * COUNTIF(ABS(official_steps - total_steps) <= 0.01 * official_steps) / COUNT(*), 1)
    AS steps_within_1pct,
  ROUND(100 * COUNTIF(ABS(official_calories - calories) <= 0.01 * official_calories) / COUNT(*), 1)
    AS calories_within_1pct,
  ROUND(100 * COUNTIF(official_very_active = very_active_minutes) / COUNT(*), 1)
    AS very_active_exact_pct,
  ROUND(100 * COUNTIF(official_fairly_active = fairly_active_minutes) / COUNT(*), 1)
    AS fairly_active_exact_pct,
  ROUND(100 * COUNTIF(official_lightly_active = lightly_active_minutes) / COUNT(*), 1)
    AS lightly_active_exact_pct,
  ROUND(100 * COUNTIF(official_sedentary = sedentary_minutes) / COUNT(*), 1)
    AS sedentary_exact_pct,
  ROUND(100 * COUNTIF(ABS(official_sedentary - sedentary_minutes) <= 5) / COUNT(*), 1)
    AS sedentary_within_5min_pct,
  ROUND(AVG(official_steps)) AS avg_steps_official,
  ROUND(AVG(total_steps))    AS avg_steps_rebuilt
FROM compared;