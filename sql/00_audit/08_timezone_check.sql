-- 08_timezone_check.sql
-- Purpose: event_date is the calendar day in the Firebase property's reporting timezone, while
-- event_timestamp is UTC. This query recovers the implied offset so the day convention used
-- for retention is documented rather than assumed.
-- Output -> data/results/08_timezone_check.csv

WITH e AS (
  SELECT
    event_date,
    DATE(TIMESTAMP_MICROS(event_timestamp))                                      AS utc_date,
    EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp))                          AS utc_hour,
    DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE(TIMESTAMP_MICROS(event_timestamp)), DAY) AS date_minus_utc_days
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
)
SELECT
  date_minus_utc_days,
  utc_hour,
  COUNT(*) AS n_events
FROM e
GROUP BY date_minus_utc_days, utc_hour
ORDER BY date_minus_utc_days, utc_hour;
-- Reading the output: if events with utc_hour >= H have date_minus_utc_days = +1 (or utc_hour < H
-- give -1), the reporting timezone is UTC+(24-H) or UTC-H respectively. Record the result in
-- docs/data_quality_log.md.
