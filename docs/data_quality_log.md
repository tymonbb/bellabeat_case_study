# Data quality log

Each row: what was observed, how it was checked, what the check showed,
and what was decided. Query numbers refer to `sql/01_data_audit.sql`.

| # | Observation | Check | Result | Decision |
|---|---|---|---|---|
| 1 | Dates stored as US-format text with AM/PM; BigQuery auto-detect failed on load | Query 1 | All 13 tables parse with `%m/%d/%Y` or `%m/%d/%Y %I:%M:%S %p`, 0 failures | Load date columns as STRING, parse explicitly in SQL |
| 2 | Period 1 daily file much smaller than hourly file | Queries 2, 3 | 457 vs 1,021 user-days. Daily file has 2 users per day until 24 Mar, 10–11 on 29–31 Mar, full coverage only from 1 Apr; hourly file has 32–34 users throughout | Rebuild period 1 daily data from minute/hourly data; validate the method on period 2, where both sources exist |
| 3 | 2016-04-12 appears in both periods | Query 4 | 24 users; period 1 values always lower (median sedentary minutes 415 vs 898), so the day is cut off in the period 1 export | Keep the period 2 version |
| 4 | Duplicate rows | Query 5 | Minute sleep: 525 (P1) and 543 (P2); sleep day: 3. All are full-row duplicates. None in daily or hourly files | Remove with `DISTINCT` |
| 5 | Days with zero steps | Query 6 | 133 of 1,373 user-days (9.7%), 122 of them with 1,440 sedentary minutes; 20 users affected | Treat as non-wear days and exclude from activity averages; final rule and sensitivity check in stage 2 |
| 6 | Activity minutes sum to exactly 1,440 on 708 days | Query 6 | Fitbit does not count sleep minutes in any activity category, so 1,440 means no sleep was recorded that day | Use as a proxy for whether the device was worn overnight |
| 7 | Uneven feature coverage | Query 7 | Activity 35 users (100%), sleep 25 (71.4%), heart rate 15 (42.9%), weight 13 (37.1%) | Report as a finding (hypotheses H2, H5); run sleep and heart-rate analyses on the subsets that have them |
| 8 | Period 1 daily file has users missing from hourly file | Query 3, Python check | User 4388161847 has 8 days in the period 1 daily file and no hourly or minute data | When rebuilding period 1, keep daily-file rows for user-days missing from minute data |
| 9 | Minute sleep has more user-days than the sleep day file | Query 2, Python check | Assigning each sleep session (`logId`) to its end date reproduces `sleepDay` for 410/410 rows: time in bed exact in all, minutes asleep exact in 396 | Rebuild period 1 nightly sleep from minute data using the wake-up date |
| 10 | Heart rate data starts late | Query 2 | Period 1 from 29 Mar only; 143 user-days in P1, 334 in P2; 15 users in total | Use for feature adoption only, not for trends |