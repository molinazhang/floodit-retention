-- 06_coverage_gaps.sql
-- Purpose: daily volume against a robust baseline so partial, missing or anomalous days stand out.
-- A day is flagged when its table is missing, its distinct-user count is < 60% or > 167% of the
-- extract-wide median, or it carries no first_open event at all. 13_new_user_cohort.sql recomputes the same flag and marks any cohort
-- with a flagged day inside its day-0..day-7 window as not eligible.
-- Output -> data/results/06_coverage_gaps.csv

WITH daily AS (
  SELECT
    PARSE_DATE('%Y%m%d', _TABLE_SUFFIX)                                        AS day,
    COUNT(*)                                                                   AS n_events,
    COUNT(DISTINCT user_pseudo_id)                                             AS n_users,
    COUNT(DISTINCT IF(event_name = 'first_open', user_pseudo_id, NULL))        AS n_first_open_users,
    COUNT(DISTINCT IF(event_name = 'user_engagement', user_pseudo_id, NULL))   AS n_engaged_users
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
  GROUP BY day
),
calendar AS (
  SELECT day
  FROM UNNEST(GENERATE_DATE_ARRAY(PARSE_DATE('%Y%m%d', '{{START_SUFFIX}}'),
                                  PARSE_DATE('%Y%m%d', '{{END_SUFFIX}}'))) AS day
),
baseline AS (
  -- Robust baseline: the median distinct-user count over the whole extract. A trailing-window
  -- median was tried first, but the June 2018 anomaly days (see docs/data_quality_log.md)
  -- contaminated it, flagging two normal days and missing one anomalous day.
  SELECT APPROX_QUANTILES(n_users, 2)[OFFSET(1)] AS baseline_median_users FROM daily
),
scored AS (
  SELECT
    c.day,
    d.n_events, d.n_users, d.n_first_open_users, d.n_engaged_users,
    d.day IS NULL                                            AS table_missing,
    b.baseline_median_users,
    ROUND(SAFE_DIVIDE(d.n_users, b.baseline_median_users), 2) AS users_vs_baseline
  FROM calendar c
  LEFT JOIN daily d USING (day)
  CROSS JOIN baseline b
)
SELECT
  *,
  -- Anomalous day = missing table, distinct users below 60% or above 1/0.6 (167%) of the
  -- baseline, or a day on which no first_open was exported at all.
  table_missing
    OR COALESCE(n_users < 0.6 * baseline_median_users, FALSE)
    OR COALESCE(n_users > baseline_median_users / 0.6, FALSE)
    OR COALESCE(n_first_open_users = 0, FALSE)                AS low_volume_flag
FROM scored
ORDER BY day;
