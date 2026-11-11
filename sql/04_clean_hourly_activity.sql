-- =====================================================================
-- 04.1 Hourly activity table (both periods)
-- Period 1 rows for 2016-04-12 excluded (truncated, see log row 3).
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.hourly_activity AS

WITH hourly AS (
  SELECT 1 AS period, s.Id AS user_id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', s.ActivityHour) AS hour_start,
         s.StepTotal AS steps, c.Calories AS calories
  FROM fitbit_raw.p1_hourly_steps AS s
  JOIN fitbit_raw.p1_hourly_calories AS c
    ON s.Id = c.Id AND s.ActivityHour = c.ActivityHour
  UNION ALL
  SELECT 2, s.Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', s.ActivityHour),
         s.StepTotal, c.Calories
  FROM fitbit_raw.p2_hourly_steps AS s
  JOIN fitbit_raw.p2_hourly_calories AS c
    ON s.Id = c.Id AND s.ActivityHour = c.ActivityHour
),

minute_intensity AS (
  SELECT 1 AS period, Id AS user_id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute) AS minute_ts,
         Intensity
  FROM fitbit_raw.p1_minute_intensities
  UNION ALL
  SELECT 2, Id,
         PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute),
         Intensity
  FROM fitbit_raw.p2_minute_intensities
),

minute_by_hour AS (
  SELECT
    period,
    user_id,
    DATETIME_TRUNC(minute_ts, HOUR) AS hour_start,
    COUNT(*)                AS recorded_minutes,
    COUNTIF(Intensity > 0)  AS active_minutes,
    COUNTIF(Intensity >= 2) AS mvpa_minutes
  FROM minute_intensity
  GROUP BY period, user_id, hour_start
)

SELECT
  h.period,
  h.user_id,
  h.hour_start,
  DATE(h.hour_start)                AS activity_date,
  EXTRACT(HOUR FROM h.hour_start)   AS hour_of_day,
  h.steps,
  h.calories,
  m.active_minutes,
  m.mvpa_minutes,
  m.recorded_minutes,
  IFNULL(d.is_valid_day, FALSE)     AS is_valid_day
FROM hourly AS h
LEFT JOIN minute_by_hour AS m
  ON h.period = m.period
 AND h.user_id = m.user_id
 AND h.hour_start = m.hour_start
LEFT JOIN fitbit_clean.daily_activity AS d
  ON h.user_id = d.user_id
 AND DATE(h.hour_start) = d.activity_date
WHERE NOT (h.period = 1 AND DATE(h.hour_start) = DATE '2016-04-12');

-- 04.2 Hourly table checks
-- Expected: period 1: 23,909 rows, 34 users; period 2: 22,099 rows, 33 users;
-- 6 rows without a full hour of minute data
SELECT
  period,
  COUNT(*)                                                AS hours,
  COUNT(DISTINCT user_id)                                 AS users,
  COUNTIF(is_valid_day)                                   AS hours_on_valid_days,
  COUNTIF(recorded_minutes IS NULL OR recorded_minutes != 60) AS incomplete_hours,
  MIN(hour_start)                                         AS first_hour,
  MAX(hour_start)                                         AS last_hour
FROM fitbit_clean.hourly_activity
GROUP BY period
ORDER BY period;

-- 04.3 One row per user and hour?
-- Expected: 46,008 rows, 46,008 unique user-hours, 35 users
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT FORMAT('%d|%t', user_id, hour_start)) AS unique_user_hours,
  COUNT(DISTINCT user_id) AS users
FROM fitbit_clean.hourly_activity;