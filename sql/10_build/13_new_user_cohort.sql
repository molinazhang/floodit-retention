-- 13_new_user_cohort.sql
-- Purpose: the new-user cohort table with day-1 and day-7 retention outcomes.
-- Creates: {{PROJECT}}.{{DATASET}}.new_user_cohort
--
-- Definitions (see docs/metric_definitions.md):
--   cohort_date      = calendar day (reporting timezone) of the user's first `first_open` event.
--   new user         = has first_open in the extract AND no event on an earlier day
--                      AND user_first_touch_timestamp (UTC) within 1 day of cohort_date.
--   retained_d1      = >= 1 active event on cohort_date + 1 (exactly that calendar day).
--   retained_d7      = >= 1 active event on cohort_date + 7 (exactly that calendar day).
--   complete_followup = cohort_date + 7 <= last extract date. Only complete cohorts are analyzed.
--   window_coverage_ok = none of days 0..7 is flagged missing/low-volume/anomalous in 06_coverage_gaps.

CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.new_user_cohort` AS
WITH extract_bounds AS (
  SELECT PARSE_DATE('%Y%m%d', '{{START_SUFFIX}}') AS extract_start,
         PARSE_DATE('%Y%m%d', '{{END_SUFFIX}}')   AS extract_end
),
first_open AS (
  SELECT
    user_pseudo_id,
    MIN(event_date)                                       AS cohort_date,
    MIN(event_ts_utc)                                     AS first_open_ts_utc,
    COUNT(*)                                              AS n_first_open_events,
    COUNT(DISTINCT event_date)                            AS n_first_open_dates
  FROM `{{PROJECT}}.{{DATASET}}.events_clean`
  WHERE event_class = 'first_open'
  GROUP BY user_pseudo_id
),
first_seen AS (
  SELECT
    user_pseudo_id,
    MIN(event_date)                                       AS first_seen_date,
    MIN(first_touch_ts_utc)                               AS first_touch_ts_utc,
    -- User attributes: ANY_VALUE over all of the user's rows (04_identifiers reports how
    -- often a user shows more than one platform; expected to be rare).
    ANY_VALUE(platform)                                   AS platform,
    ANY_VALUE(device_category)                            AS device_category,
    ANY_VALUE(os)                                         AS os,
    ANY_VALUE(country)                                    AS country,
    ANY_VALUE(language)                                   AS language,
    ANY_VALUE(app_version)                                AS app_version,
    ANY_VALUE(traffic_source)                             AS traffic_source,
    ANY_VALUE(traffic_medium)                             AS traffic_medium
  FROM `{{PROJECT}}.{{DATASET}}.events_clean`
  GROUP BY user_pseudo_id
),
-- Daily coverage flags, recomputed here so this table is self-contained (same rule as
-- sql/00_audit/06_coverage_gaps.sql: missing table, users < 60% or > 167% of the extract-wide
-- median, or a day with no first_open exported).
daily AS (
  SELECT
    event_date                                                        AS day,
    COUNT(DISTINCT user_pseudo_id)                                    AS n_users,
    COUNT(DISTINCT IF(event_class = 'first_open', user_pseudo_id, NULL)) AS n_first_open_users
  FROM `{{PROJECT}}.{{DATASET}}.events_clean`
  GROUP BY day
),
baseline AS (
  SELECT APPROX_QUANTILES(n_users, 2)[OFFSET(1)] AS baseline_median_users FROM daily
),
calendar AS (
  SELECT day
  FROM extract_bounds b, UNNEST(GENERATE_DATE_ARRAY(b.extract_start, b.extract_end)) AS day
),
coverage AS (
  SELECT
    c.day,
    d.day IS NULL
      OR COALESCE(d.n_users < 0.6 * b.baseline_median_users, FALSE)
      OR COALESCE(d.n_users > b.baseline_median_users / 0.6, FALSE)
      OR COALESCE(d.n_first_open_users = 0, FALSE)                    AS bad_day
  FROM calendar c
  LEFT JOIN daily d USING (day)
  CROSS JOIN baseline b
),
cohort AS (
  SELECT
    fo.user_pseudo_id,
    fo.cohort_date,
    DATE_TRUNC(fo.cohort_date, WEEK(MONDAY))              AS cohort_week,
    IF(fo.cohort_date <= DATE '{{EXPLORATORY_END}}', 'exploratory', 'validation') AS phase,
    fo.first_open_ts_utc,
    EXTRACT(HOUR FROM fo.first_open_ts_utc)               AS first_open_hour_utc,
    fs.platform, fs.device_category, fs.os, fs.country, fs.language, fs.app_version,
    fs.traffic_source, fs.traffic_medium,
    fo.n_first_open_events, fo.n_first_open_dates,
    fs.first_seen_date,
    DATE(fs.first_touch_ts_utc)                           AS first_touch_date_utc,
    -- Eligibility flags
    fs.first_seen_date = fo.cohort_date                   AS first_open_is_first_seen,
    (fs.first_touch_ts_utc IS NULL
      OR ABS(DATE_DIFF(DATE(fs.first_touch_ts_utc), fo.cohort_date, DAY)) <= 1) AS first_touch_consistent,
    DATE_ADD(fo.cohort_date, INTERVAL 7 DAY) <= b.extract_end AS complete_followup,
    fo.cohort_date BETWEEN DATE '{{COHORT_START}}' AND DATE '{{COHORT_END}}' AS in_cohort_window
  FROM first_open fo
  JOIN first_seen fs USING (user_pseudo_id)
  CROSS JOIN extract_bounds b
),
outcomes AS (
  SELECT
    c.user_pseudo_id,
    -- Conditional aggregation over the LEFT JOIN to user_day
    COUNTIF(ud.activity_date = DATE_ADD(c.cohort_date, INTERVAL 1 DAY) AND ud.n_active_events   > 0) > 0 AS retained_d1,
    COUNTIF(ud.activity_date = DATE_ADD(c.cohort_date, INTERVAL 7 DAY) AND ud.n_active_events   > 0) > 0 AS retained_d7,
    COUNTIF(ud.activity_date = DATE_ADD(c.cohort_date, INTERVAL 1 DAY) AND ud.n_gameplay_events > 0) > 0 AS retained_d1_gameplay,
    COUNTIF(ud.activity_date = DATE_ADD(c.cohort_date, INTERVAL 7 DAY) AND ud.n_gameplay_events > 0) > 0 AS retained_d7_gameplay,
    COUNT(DISTINCT IF(ud.activity_date BETWEEN DATE_ADD(c.cohort_date, INTERVAL 1 DAY)
                                          AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
                      AND ud.n_active_events > 0, ud.activity_date, NULL))                        AS active_days_d1_d7,
    COUNTIF(ud.activity_date BETWEEN c.cohort_date AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
            AND ud.app_removed) > 0                                                               AS app_removed_d0_d7
  FROM cohort c
  LEFT JOIN `{{PROJECT}}.{{DATASET}}.user_day` ud
    ON ud.user_pseudo_id = c.user_pseudo_id
   AND ud.activity_date BETWEEN c.cohort_date AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
  GROUP BY c.user_pseudo_id
),
window_cov AS (
  SELECT
    c.user_pseudo_id,
    LOGICAL_OR(cov.bad_day) AS any_bad_day_in_window
  FROM cohort c
  JOIN coverage cov
    ON cov.day BETWEEN c.cohort_date AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
  GROUP BY c.user_pseudo_id
)
SELECT
  c.*,
  NOT COALESCE(w.any_bad_day_in_window, TRUE)           AS window_coverage_ok,
  c.first_open_is_first_seen AND c.first_touch_consistent AND c.complete_followup
    AND c.in_cohort_window AND NOT COALESCE(w.any_bad_day_in_window, TRUE) AS eligible,
  o.retained_d1, o.retained_d7, o.retained_d1_gameplay, o.retained_d7_gameplay,
  o.active_days_d1_d7, o.app_removed_d0_d7
FROM cohort c
LEFT JOIN outcomes o USING (user_pseudo_id)
LEFT JOIN window_cov w USING (user_pseudo_id);
