# Loading raw data into BigQuery

Dataset: `fitbit_raw` (location: EU). Source: FitBit Fitness Tracker Data
(Kaggle, Mobius, CC0), files unzipped to `data/raw/period_1` and `data/raw/period_2`.

Load settings for every table:
- Create table → Upload → CSV
- Schema: defined manually (auto-detect disabled), date/time columns kept as STRING
  and parsed later in SQL (`sql/01_...`)
- Advanced options → Header rows to skip: 1

Why manual schema: auto-detect inferred date columns such as `ActivityHour`
(e.g. `3/12/2016 1:00:00 AM`) as a timestamp type and failed to parse the
AM/PM format, rejecting every row.

| Table | Source file | Rows |
|---|---|---|
| p1_daily_activity | period_1/dailyActivity_merged.csv | 457 |
| p2_daily_activity | period_2/dailyActivity_merged.csv | 940 |
| p1_hourly_steps | period_1/hourlySteps_merged.csv | 24,084 |
| p2_hourly_steps | period_2/hourlySteps_merged.csv | 22,099 |
| p1_hourly_calories | period_1/hourlyCalories_merged.csv | 24,084 |
| p2_hourly_calories | period_2/hourlyCalories_merged.csv | 22,099 |
| p1_minute_intensities | period_1/minuteIntensitiesNarrow_merged.csv | 1,445,040 |
| p2_minute_intensities | period_2/minuteIntensitiesNarrow_merged.csv | 1,325,580 |
| p1_minute_sleep | period_1/minuteSleep_merged.csv | 198,559 |
| p2_minute_sleep | period_2/minuteSleep_merged.csv | 188,521 |
| p2_sleep_day | period_2/sleepDay_merged.csv | 413 |
| p1_weight_log | period_1/weightLogInfo_merged.csv | 33 |
| p2_weight_log | period_2/weightLogInfo_merged.csv | 67 |
| p1_heartrate_seconds | period_1/heartrate_seconds_merged.csv | 1,154,681 |
| p2_heartrate_seconds | period_2/heartrate_seconds_merged.csv | 2,483,658 |

Schemas: see `sql/schemas/` (one JSON file per source file type).

Not loaded (duplicate or derivable information): dailySteps, dailyCalories,
dailyIntensities (identical to dailyActivity), minute*Wide (same data as
*Narrow, pivoted), hourlyIntensities (derivable from minute intensities),
minuteStepsNarrow, minuteCaloriesNarrow, minuteMETsNarrow (not needed at
minute resolution for the analysis).

Load check query:

```sql
SELECT table_id, row_count, ROUND(size_bytes / 1e6, 1) AS size_mb
FROM `fitbit_raw.__TABLES__`
ORDER BY table_id;
```