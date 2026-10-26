-- 23_retention_by_behavior_group.sql
-- Purpose: D1/D7 retention by day-0 behavior group, overall and sliced by phase
-- (exploratory vs validation cohorts) and platform. Group sizes and standard errors are
-- reported so small cells are visible. Wilson intervals and bootstrap differences are
-- computed in python/analysis.py from the user-level export.
-- Output -> data/results/23_retention_by_behavior_group.csv

SELECT
  COALESCE(phase, 'ALL')                                        AS phase,
  COALESCE(platform, 'ALL')                                     AS platform,
  behavior_group,
  COUNT(*)                                                      AS n_users,
  COUNTIF(retained_d1)                                          AS n_retained_d1,
  COUNTIF(retained_d7)                                          AS n_retained_d7,
  ROUND(AVG(CAST(retained_d1 AS INT64)), 4)                     AS d1_retention,
  ROUND(AVG(CAST(retained_d7 AS INT64)), 4)                     AS d7_retention,
  ROUND(SQRT(AVG(CAST(retained_d7 AS INT64)) * (1 - AVG(CAST(retained_d7 AS INT64))) / COUNT(*)), 4) AS d7_se,
  ROUND(AVG(d0_engagement_sec), 1)                              AS mean_d0_engagement_sec,
  ROUND(AVG(d0_levels_started), 2)                              AS mean_d0_levels_started
FROM `{{PROJECT}}.{{DATASET}}.cohort_day0_features`
WHERE eligible
GROUP BY GROUPING SETS ((behavior_group), (phase, behavior_group), (platform, behavior_group), (phase, platform, behavior_group))
ORDER BY phase, platform, behavior_group;
