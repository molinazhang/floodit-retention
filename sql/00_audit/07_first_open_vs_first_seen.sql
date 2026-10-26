-- 07_first_open_vs_first_seen.sql
-- Purpose: separate genuinely new users (a first_open event inside the extract) from users
-- who are merely first observed in the extract (installed before it started, or whose
-- first_open was not exported). Also checks user_first_touch_timestamp agreement.
-- Output -> data/results/07_first_open_vs_first_seen.csv

WITH per_user AS (
  SELECT
    user_pseudo_id,
    MIN(event_date)                                                   AS first_seen_date,
    MIN(IF(event_name = 'first_open', event_date, NULL))              AS first_open_date,
    COUNTIF(event_name = 'first_open')                                AS n_first_open_events,
    COUNT(DISTINCT IF(event_name = 'first_open', event_date, NULL))   AS n_first_open_dates,
    FORMAT_DATE('%Y%m%d', DATE(TIMESTAMP_MICROS(MIN(user_first_touch_timestamp)))) AS first_touch_date_utc
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN first_open_date IS NULL                      THEN '1_no_first_open_in_extract (pre-existing or unexported)'
    WHEN first_open_date = first_seen_date            THEN '2_first_open_on_first_seen_day (new user)'
    ELSE                                                   '3_first_open_after_first_seen_day (suspicious)'
  END AS user_type,
  CASE
    WHEN first_touch_date_utc IS NULL                 THEN 'first_touch_null'
    WHEN first_touch_date_utc <  '{{START_SUFFIX}}'   THEN 'first_touch_before_extract'
    WHEN first_touch_date_utc =  first_open_date      THEN 'first_touch_equals_first_open'
    WHEN first_open_date IS NOT NULL
         AND ABS(DATE_DIFF(PARSE_DATE('%Y%m%d', first_touch_date_utc),
                           PARSE_DATE('%Y%m%d', first_open_date), DAY)) <= 1
                                                      THEN 'first_touch_within_1_day_of_first_open'
    ELSE                                                   'first_touch_other'
  END AS first_touch_check,
  COUNT(*)                                            AS n_users,
  COUNTIF(n_first_open_dates > 1)                     AS n_users_multiple_first_open_dates,
  ROUND(AVG(n_first_open_events), 3)                  AS avg_first_open_events
FROM per_user
GROUP BY user_type, first_touch_check
ORDER BY user_type, first_touch_check;
