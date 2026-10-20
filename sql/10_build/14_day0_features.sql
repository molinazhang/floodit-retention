-- 14_day0_features.sql
-- Purpose: day-zero (cohort-day) behavior features for every cohort user, plus the behavior
-- groups used in the comparison. Every column here is computed from events on cohort_date
-- only, so no outcome-period information leaks into the group definitions.
-- Creates: {{PROJECT}}.{{DATASET}}.cohort_day0_features
--
-- Behavior-group definitions are EXPLORATORY choices made before looking at retention by
-- group on the validation cohorts (docs/analysis_decisions.md).

CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.cohort_day0_features` AS
WITH c AS (
  SELECT * FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort`
),
d0 AS (
  -- Day-0 aggregates come straight from the user-day table (join on user AND cohort date).
  SELECT ud.*
  FROM `{{PROJECT}}.{{DATASET}}.user_day` ud
  JOIN c ON ud.user_pseudo_id = c.user_pseudo_id AND ud.activity_date = c.cohort_date
),
level_events AS (
  SELECT e.user_pseudo_id, e.event_ts_utc, e.event_class
  FROM `{{PROJECT}}.{{DATASET}}.events_clean` e
  JOIN c USING (user_pseudo_id)
  WHERE e.event_date = c.cohort_date
    AND e.event_class IN ('level_start', 'level_complete', 'level_fail', 'level_reset', 'level_retry', 'level_end')
),
first_start AS (
  SELECT user_pseudo_id, MIN(IF(event_class = 'level_start', event_ts_utc, NULL)) AS first_level_start_ts_utc
  FROM level_events
  GROUP BY user_pseudo_id
),
first_outcome AS (
  -- Window function: the first outcome event after the first level start.
  SELECT user_pseudo_id, event_class AS first_level_outcome
  FROM (
    SELECT
      le.user_pseudo_id, le.event_class,
      ROW_NUMBER() OVER (PARTITION BY le.user_pseudo_id ORDER BY le.event_ts_utc) AS rn
    FROM level_events le
    JOIN first_start fs USING (user_pseudo_id)
    WHERE le.event_ts_utc > fs.first_level_start_ts_utc
      AND le.event_class IN ('level_complete', 'level_fail', 'level_reset', 'level_retry')
  )
  WHERE rn = 1
)
SELECT
  c.*,
  -- Day-0 activity counts (NULL -> 0 for users with no user_day row on cohort day).
  COALESCE(d0.n_events, 0)             AS d0_n_events,
  COALESCE(d0.n_active_events, 0)      AS d0_active_events,
  COALESCE(d0.n_gameplay_events, 0)    AS d0_gameplay_events,
  COALESCE(d0.engagement_sec, 0)       AS d0_engagement_sec,
  COALESCE(d0.n_sessions, 0)           AS d0_sessions,
  COALESCE(d0.levels_started, 0)       AS d0_levels_started,
  COALESCE(d0.levels_completed, 0)     AS d0_levels_completed,
  COALESCE(d0.levels_failed, 0)        AS d0_levels_failed,
  COALESCE(d0.levels_reset, 0)         AS d0_levels_reset,
  COALESCE(d0.levels_retried, 0)       AS d0_levels_retried,
  COALESCE(d0.extra_steps_used, 0)     AS d0_extra_steps,
  COALESCE(d0.no_more_extra_steps, 0)  AS d0_no_more_extra_steps,
  COALESCE(d0.ad_rewards, 0)           AS d0_ad_rewards,
  COALESCE(d0.post_scores, 0)          AS d0_post_scores,
  COALESCE(d0.economy_events, 0)       AS d0_economy_events,
  COALESCE(d0.social_events, 0)        AS d0_social_events,
  COALESCE(d0.hit_5_levels_milestone, FALSE) AS d0_hit_5_levels,
  COALESCE(d0.app_removed, FALSE)      AS d0_app_removed,
  d0.max_score                         AS d0_max_score,
  TIMESTAMP_DIFF(d0.last_active_ts_utc, d0.first_active_ts_utc, SECOND) AS d0_active_span_sec,
  TIMESTAMP_DIFF(fs.first_level_start_ts_utc, c.first_open_ts_utc, SECOND) AS d0_secs_to_first_level,
  COALESCE(fo.first_level_outcome,
           IF(fs.first_level_start_ts_utc IS NULL, 'not_started', 'started_no_outcome')) AS d0_first_level_outcome,
  -- Behavior group v1: how far did the user get on day 0 (progress-based, 4 groups).
  CASE
    WHEN COALESCE(d0.levels_started, 0) = 0     THEN 'A_no_level_started'
    WHEN COALESCE(d0.levels_completed, 0) = 0   THEN 'B_started_none_completed'
    WHEN d0.levels_completed BETWEEN 1 AND 2    THEN 'C_completed_1_to_2'
    ELSE                                              'D_completed_3_plus'
  END AS behavior_group,
  -- Behavior group v2: what happened on the very first level (difficulty-based).
  CASE
    WHEN fs.first_level_start_ts_utc IS NULL        THEN 'not_started'
    WHEN fo.first_level_outcome = 'level_complete'  THEN 'first_level_completed'
    WHEN fo.first_level_outcome = 'level_fail'      THEN 'first_level_failed'
    WHEN fo.first_level_outcome IN ('level_reset', 'level_retry') THEN 'first_level_reset_or_retry'
    ELSE                                                  'started_no_outcome'
  END AS first_level_group
FROM c
LEFT JOIN d0           USING (user_pseudo_id)
LEFT JOIN first_start  fs USING (user_pseudo_id)
LEFT JOIN first_outcome fo USING (user_pseudo_id);
