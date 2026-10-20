-- 21_retention_by_cohort.sql
-- Purpose: daily-cohort retention curve inputs. Eligible users only (complete follow-up,
-- clean coverage window, verified new users).
-- Output -> data/results/21_retention_by_cohort.csv

SELECT
  cohort_date,
  cohort_week,
  phase,
  COUNT(*)                                           AS n_users,
  COUNTIF(retained_d1)                               AS n_retained_d1,
  COUNTIF(retained_d7)                               AS n_retained_d7,
  ROUND(AVG(CAST(retained_d1 AS INT64)), 4)          AS d1_retention,
  ROUND(AVG(CAST(retained_d7 AS INT64)), 4)          AS d7_retention,
  ROUND(AVG(CAST(retained_d7_gameplay AS INT64)), 4) AS d7_retention_gameplay_only,
  ROUND(AVG(active_days_d1_d7), 3)                   AS mean_active_days_d1_d7,
  COUNTIF(platform = 'ANDROID')                      AS n_android,
  COUNTIF(platform = 'IOS')                          AS n_ios
FROM `{{PROJECT}}.{{DATASET}}.cohort_day0_features`
WHERE eligible
GROUP BY cohort_date, cohort_week, phase
ORDER BY cohort_date;
