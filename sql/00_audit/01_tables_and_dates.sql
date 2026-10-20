-- 01_tables_and_dates.sql
-- Purpose: establish which daily tables exist, their row counts, and the real date coverage.
-- Cost: scans only user_pseudo_id + event_timestamp (small). The wildcard filter is wide on
-- purpose so missing or extra tables (e.g. intraday) show up.
-- Output -> data/results/01_tables_and_dates.csv

SELECT
  _TABLE_SUFFIX                                                   AS table_suffix,
  COUNT(*)                                                        AS n_events,
  COUNT(DISTINCT user_pseudo_id)                                  AS n_users,
  TIMESTAMP_MICROS(MIN(event_timestamp))                          AS min_event_ts_utc,
  TIMESTAMP_MICROS(MAX(event_timestamp))                          AS max_event_ts_utc,
  COUNTIF(event_date != _TABLE_SUFFIX)                            AS n_events_date_mismatch
FROM `{{SOURCE_TABLE}}`
GROUP BY table_suffix
ORDER BY table_suffix;
