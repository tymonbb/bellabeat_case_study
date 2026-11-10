-- =====================================================================
-- 2.3 Final daily activity table
-- Original daily files take priority; rebuilt data fills period-1 gaps.
-- Decisions: docs/data_quality_log.md, rows 2, 3, 5, 8 and 11.
-- =====================================================================
CREATE OR REPLACE TABLE fitbit_clean.daily_activity AS

WITH official AS (
  SELECT
    1 AS period,
    Id AS user_id,
    PARSE_DATE('%m/%d/%Y', ActivityDate) AS activity_date,
    TotalSteps           AS total_steps,
    Calories             AS calories,
    VeryActiveMinutes    AS very_active_minutes,
    FairlyActiveMinutes  AS fairly_active_minutes,
    LightlyActiveMinutes AS lightly_active_minutes,
    SedentaryMinutes     AS sedentary_minutes,
    'daily_file'         AS data_source
  FROM fitbit_raw.p1_daily_activity
  WHERE ActivityDate != '4/12/2016'          -- truncated in period 1 export
  UNION ALL
  SELECT
    2, Id, PARSE_DATE('%m/%d/%Y', ActivityDate),
    TotalSteps, Calories, VeryActiveMinutes, FairlyActiveMinutes,
    LightlyActiveMinutes, SedentaryMinutes, 'daily_file'
  FROM fitbit_raw.p2_daily_activity
),

rebuilt_fill AS (
  SELECT
    r.period, r.user_id, r.activity_date,
    r.total_steps, r.calories, r.very_active_minutes, r.fairly_active_minutes,
    r.lightly_active_minutes, r.sedentary_minutes,
    'rebuilt_from_minutes' AS data_source
  FROM fitbit_clean.daily_rebuilt AS r
  WHERE r.period = 1
    AND r.activity_date != DATE '2016-04-12'
    AND NOT EXISTS (
      SELECT 1
      FROM official AS o
      WHERE o.user_id = r.user_id
        AND o.activity_date = r.activity_date
    )
),

combined AS (
  SELECT * FROM official
  UNION ALL
  SELECT * FROM rebuilt_fill
)

SELECT
  c.*,
  c.very_active_minutes + c.fairly_active_minutes + c.lightly_active_minutes
    AS active_minutes,
  c.very_active_minutes + c.fairly_active_minutes + c.lightly_active_minutes
    + c.sedentary_minutes AS tracked_minutes,
  r.recorded_minutes,
  r.sleep_log_minutes,
  c.total_steps = 0 AS is_zero_step_day,
  IFNULL(r.recorded_minutes, 1440) < 1440 AS is_partial_day,
  c.total_steps > 0 AND IFNULL(r.recorded_minutes, 1440) = 1440 AS is_valid_day
FROM combined AS c
LEFT JOIN fitbit_clean.daily_rebuilt AS r
  ON c.period = r.period
 AND c.user_id = r.user_id
 AND c.activity_date = r.activity_date;

-- 2.4 Checks on the final daily table
SELECT
  data_source,
  period,
  COUNT(*)                    AS user_days,
  COUNT(DISTINCT user_id)     AS users,
  COUNTIF(is_zero_step_day)   AS zero_step_days,
  COUNTIF(is_partial_day)     AS partial_days,
  COUNTIF(is_valid_day)       AS valid_days
FROM fitbit_clean.daily_activity
GROUP BY data_source, period
ORDER BY period, data_source;

-- 2.5 One row per user and day?
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT FORMAT('%d|%t', user_id, activity_date)) AS unique_user_days,
  COUNT(DISTINCT user_id) AS users,
  MIN(activity_date) AS first_date,
  MAX(activity_date) AS last_date
FROM fitbit_clean.daily_activity;