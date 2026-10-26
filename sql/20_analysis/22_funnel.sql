-- 22_funnel.sql
-- Purpose: day-0 progression funnel for eligible new users, overall and by platform
-- (GROUPING SETS). Steps are cumulative and ordered; each step implies the previous one.
-- Output -> data/results/22_funnel.csv

SELECT
  COALESCE(platform, 'ALL')                                   AS platform,
  COUNT(*)                                                    AS step0_first_open,
  COUNTIF(d0_active_events > 0)                               AS step1_any_active_event,
  COUNTIF(d0_levels_started >= 1)                             AS step2_started_level,
  COUNTIF(d0_levels_completed >= 1)                           AS step3_completed_1_level,
  COUNTIF(d0_levels_completed >= 3)                           AS step4_completed_3_levels,
  COUNTIF(d0_levels_completed >= 5 OR d0_hit_5_levels)        AS step5_completed_5_levels,
  -- Secondary day-0 behaviors (not funnel steps)
  COUNTIF(d0_levels_failed >= 1)                              AS n_failed_any_level,
  COUNTIF(d0_extra_steps >= 1)                                AS n_used_extra_steps,
  COUNTIF(d0_ad_rewards >= 1)                                 AS n_ad_reward,
  COUNTIF(d0_app_removed)                                     AS n_app_removed_d0
FROM `{{PROJECT}}.{{DATASET}}.cohort_day0_features`
WHERE eligible
GROUP BY GROUPING SETS ((), (platform))
ORDER BY platform;
