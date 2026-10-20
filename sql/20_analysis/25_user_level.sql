-- 25_user_level.sql
-- Purpose: one row per cohort user (all users in the cohort window, with eligibility flags) for
-- the Python analysis and the secondary ML model. Identifiers are already pseudonymous.
-- Output -> data/results/25_user_level.csv

SELECT
  user_pseudo_id, cohort_date, cohort_week, phase,
  platform, device_category, os, country, language, app_version, traffic_source, traffic_medium,
  first_open_hour_utc,
  first_open_is_first_seen, first_touch_consistent, complete_followup, in_cohort_window,
  window_coverage_ok, eligible,
  retained_d1, retained_d7, retained_d1_gameplay, retained_d7_gameplay,
  active_days_d1_d7, app_removed_d0_d7,
  d0_n_events, d0_active_events, d0_gameplay_events, d0_engagement_sec, d0_sessions,
  d0_levels_started, d0_levels_completed, d0_levels_failed, d0_levels_reset, d0_levels_retried,
  d0_extra_steps, d0_no_more_extra_steps, d0_ad_rewards, d0_post_scores, d0_economy_events,
  d0_social_events, d0_hit_5_levels, d0_app_removed, d0_max_score, d0_active_span_sec,
  d0_secs_to_first_level, d0_first_level_outcome,
  behavior_group, first_level_group
FROM `{{PROJECT}}.{{DATASET}}.cohort_day0_features`
WHERE in_cohort_window
ORDER BY cohort_date, user_pseudo_id;
