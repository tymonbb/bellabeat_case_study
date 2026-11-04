-- =====================================================================
-- 1. Date parsing check
-- Every text date/time must convert to a real DATE or DATETIME.
-- =====================================================================
SELECT 'p1_daily_activity' AS table_name,
       COUNT(*) AS total_rows,
       COUNTIF(SAFE.PARSE_DATE('%m/%d/%Y', ActivityDate) IS NULL) AS failed_parses
FROM fitbit_raw.p1_daily_activity
UNION ALL
SELECT 'p2_daily_activity', COUNT(*),
       COUNTIF(SAFE.PARSE_DATE('%m/%d/%Y', ActivityDate) IS NULL)
FROM fitbit_raw.p2_daily_activity
UNION ALL
SELECT 'p1_hourly_steps', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityHour) IS NULL)
FROM fitbit_raw.p1_hourly_steps
UNION ALL
SELECT 'p2_hourly_steps', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityHour) IS NULL)
FROM fitbit_raw.p2_hourly_steps
UNION ALL
SELECT 'p1_minute_intensities', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute) IS NULL)
FROM fitbit_raw.p1_minute_intensities
UNION ALL
SELECT 'p2_minute_intensities', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityMinute) IS NULL)
FROM fitbit_raw.p2_minute_intensities
UNION ALL
SELECT 'p1_minute_sleep', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date) IS NULL)
FROM fitbit_raw.p1_minute_sleep
UNION ALL
SELECT 'p2_minute_sleep', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date) IS NULL)
FROM fitbit_raw.p2_minute_sleep
UNION ALL
SELECT 'p2_sleep_day', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', SleepDay) IS NULL)
FROM fitbit_raw.p2_sleep_day
UNION ALL
SELECT 'p1_weight_log', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date) IS NULL)
FROM fitbit_raw.p1_weight_log
UNION ALL
SELECT 'p2_weight_log', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date) IS NULL)
FROM fitbit_raw.p2_weight_log
UNION ALL
SELECT 'p1_heartrate_seconds', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time) IS NULL)
FROM fitbit_raw.p1_heartrate_seconds
UNION ALL
SELECT 'p2_heartrate_seconds', COUNT(*),
       COUNTIF(SAFE.PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time) IS NULL)
FROM fitbit_raw.p2_heartrate_seconds;

-- =====================================================================
-- 2. Coverage by source and period
-- Users, user-days and date range for each data source.
-- =====================================================================
WITH observations AS (
  SELECT 'daily_activity' AS source, 1 AS period, Id,
         PARSE_DATE('%m/%d/%Y', ActivityDate) AS activity_date
  FROM fitbit_raw.p1_daily_activity
  UNION ALL
  SELECT 'daily_activity', 2, Id, PARSE_DATE('%m/%d/%Y', ActivityDate)
  FROM fitbit_raw.p2_daily_activity
  UNION ALL
  SELECT 'hourly_steps', 1, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityHour))
  FROM fitbit_raw.p1_hourly_steps
  UNION ALL
  SELECT 'hourly_steps', 2, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityHour))
  FROM fitbit_raw.p2_hourly_steps
  UNION ALL
  SELECT 'minute_sleep', 1, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date))
  FROM fitbit_raw.p1_minute_sleep
  UNION ALL
  SELECT 'minute_sleep', 2, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', date))
  FROM fitbit_raw.p2_minute_sleep
  UNION ALL
  SELECT 'sleep_day', 2, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', SleepDay))
  FROM fitbit_raw.p2_sleep_day
  UNION ALL
  SELECT 'heartrate', 1, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time))
  FROM fitbit_raw.p1_heartrate_seconds
  UNION ALL
  SELECT 'heartrate', 2, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Time))
  FROM fitbit_raw.p2_heartrate_seconds
  UNION ALL
  SELECT 'weight_log', 1, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date))
  FROM fitbit_raw.p1_weight_log
  UNION ALL
  SELECT 'weight_log', 2, Id,
         DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', Date))
  FROM fitbit_raw.p2_weight_log
)
SELECT
  source,
  period,
  COUNT(DISTINCT Id) AS users,
  COUNT(DISTINCT FORMAT('%d|%t', Id, activity_date)) AS user_days,
  MIN(activity_date) AS first_date,
  MAX(activity_date) AS last_date
FROM observations
GROUP BY source, period
ORDER BY source, period;

-- =====================================================================
-- 3. Period 1: users per date, daily file vs hourly file
-- Shows that the daily file is incomplete before 2016-04-01.
-- =====================================================================
WITH daily AS (
  SELECT PARSE_DATE('%m/%d/%Y', ActivityDate) AS activity_date,
         COUNT(DISTINCT Id) AS users_daily_file
  FROM fitbit_raw.p1_daily_activity
  GROUP BY activity_date
),
hourly AS (
  SELECT DATE(PARSE_DATETIME('%m/%d/%Y %I:%M:%S %p', ActivityHour)) AS activity_date,
         COUNT(DISTINCT Id) AS users_hourly_file
  FROM fitbit_raw.p1_hourly_steps
  GROUP BY activity_date
)
SELECT
  activity_date,
  IFNULL(d.users_daily_file, 0) AS users_daily_file,
  h.users_hourly_file
FROM hourly AS h
LEFT JOIN daily AS d USING (activity_date)
ORDER BY activity_date;

-- =====================================================================
-- 4. Overlapping date 2016-04-12 in both periods
-- Period 1 export appears to cut this day off mid-day.
-- =====================================================================
SELECT
  p1.Id,
  p1.TotalSteps       AS steps_period_1,
  p2.TotalSteps       AS steps_period_2,
  p1.SedentaryMinutes AS sedentary_period_1,
  p2.SedentaryMinutes AS sedentary_period_2
FROM fitbit_raw.p1_daily_activity AS p1
JOIN fitbit_raw.p2_daily_activity AS p2
  ON p1.Id = p2.Id
 AND p1.ActivityDate = p2.ActivityDate
WHERE p1.ActivityDate = '4/12/2016'
ORDER BY p1.Id;

-- =====================================================================
-- 5. Duplicates
-- duplicate_keys: repeated (Id, timestamp) pairs
-- full_duplicates: rows identical in every column
-- =====================================================================
SELECT 'p1_minute_sleep' AS table_name,
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, date)) AS duplicate_keys,
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t)) AS full_duplicates
FROM fitbit_raw.p1_minute_sleep AS t
UNION ALL
SELECT 'p2_minute_sleep',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, date)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p2_minute_sleep AS t
UNION ALL
SELECT 'p2_sleep_day',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, SleepDay)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p2_sleep_day AS t
UNION ALL
SELECT 'p1_daily_activity',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, ActivityDate)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p1_daily_activity AS t
UNION ALL
SELECT 'p2_daily_activity',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, ActivityDate)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p2_daily_activity AS t
UNION ALL
SELECT 'p1_hourly_steps',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, ActivityHour)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p1_hourly_steps AS t
UNION ALL
SELECT 'p2_hourly_steps',
       COUNT(*) - COUNT(DISTINCT FORMAT('%d|%s', Id, ActivityHour)),
       COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))
FROM fitbit_raw.p2_hourly_steps AS t;

-- =====================================================================
-- 6. Likely non-wear days in daily activity (both periods)
-- Period 1 row for 2016-04-12 excluded (incomplete, see query 4).
-- =====================================================================
WITH daily AS (
  SELECT Id, TotalSteps, SedentaryMinutes,
         VeryActiveMinutes + FairlyActiveMinutes
           + LightlyActiveMinutes + SedentaryMinutes AS tracked_minutes
  FROM fitbit_raw.p1_daily_activity
  WHERE ActivityDate != '4/12/2016'
  UNION ALL
  SELECT Id, TotalSteps, SedentaryMinutes,
         VeryActiveMinutes + FairlyActiveMinutes
           + LightlyActiveMinutes + SedentaryMinutes
  FROM fitbit_raw.p2_daily_activity
)
SELECT
  COUNT(*)                                           AS user_days,
  COUNTIF(TotalSteps = 0)                            AS zero_step_days,
  COUNTIF(TotalSteps = 0 AND SedentaryMinutes = 1440) AS zero_steps_full_day_sedentary,
  COUNT(DISTINCT IF(TotalSteps = 0, Id, NULL))       AS users_with_zero_step_days,
  COUNTIF(tracked_minutes = 1440)                    AS days_with_1440_tracked_minutes
FROM daily;

-- =====================================================================
-- 7. Feature adoption: how many users have any data for each feature
-- =====================================================================
WITH users_by_feature AS (
  SELECT 'activity' AS feature, Id FROM fitbit_raw.p1_daily_activity
  UNION DISTINCT SELECT 'activity',   Id FROM fitbit_raw.p2_daily_activity
  UNION DISTINCT SELECT 'activity',   Id FROM fitbit_raw.p1_hourly_steps
  UNION DISTINCT SELECT 'sleep',      Id FROM fitbit_raw.p1_minute_sleep
  UNION DISTINCT SELECT 'sleep',      Id FROM fitbit_raw.p2_minute_sleep
  UNION DISTINCT SELECT 'heart_rate', Id FROM fitbit_raw.p1_heartrate_seconds
  UNION DISTINCT SELECT 'heart_rate', Id FROM fitbit_raw.p2_heartrate_seconds
  UNION DISTINCT SELECT 'weight_log', Id FROM fitbit_raw.p1_weight_log
  UNION DISTINCT SELECT 'weight_log', Id FROM fitbit_raw.p2_weight_log
),
all_users AS (
  SELECT COUNT(DISTINCT Id) AS n FROM users_by_feature
)
SELECT
  feature,
  COUNT(DISTINCT Id) AS users,
  ROUND(100 * COUNT(DISTINCT Id) / (SELECT n FROM all_users), 1) AS pct_of_users
FROM users_by_feature
GROUP BY feature
ORDER BY users DESC;