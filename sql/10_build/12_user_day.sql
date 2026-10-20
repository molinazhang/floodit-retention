-- 12_user_day.sql
-- Purpose: one row per user per calendar day with activity counts. This is the grain at which
-- retention is defined ("did the user have >= 1 active event on day k").
-- Creates: {{PROJECT}}.{{DATASET}}.user_day

CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.user_day`
-- No PARTITION BY activity_date: BigQuery sandbox tables carry a 60-day partition expiration, which
-- deletes 2018 partitions at creation time (the first build produced an empty table). The table
-- is small (< 2 GB), so clustering alone is sufficient.
CLUSTER BY user_pseudo_id
AS
SELECT
  user_pseudo_id,
  event_date                                                        AS activity_date,
  ANY_VALUE(platform)                                               AS platform,
  COUNT(*)                                                          AS n_events,
  -- Conditional aggregation
  COUNTIF(is_active)                                                AS n_active_events,
  COUNTIF(is_gameplay)                                              AS n_gameplay_events,
  COUNTIF(event_class = 'level_start')                              AS levels_started,
  COUNTIF(event_class = 'level_complete')                           AS levels_completed,
  COUNTIF(event_class = 'level_fail')                               AS levels_failed,
  COUNTIF(event_class = 'level_reset')                              AS levels_reset,
  COUNTIF(event_class = 'level_retry')                              AS levels_retried,
  COUNTIF(event_class = 'extra_steps')                              AS extra_steps_used,
  COUNTIF(event_class = 'no_more_extra_steps')                      AS no_more_extra_steps,
  COUNTIF(event_class = 'ad_reward')                                AS ad_rewards,
  COUNTIF(event_class = 'post_score')                               AS post_scores,
  COUNTIF(event_class = 'economy')                                  AS economy_events,
  COUNTIF(event_class = 'social')                                   AS social_events,
  COUNTIF(event_class = 'milestone_5_levels') > 0                   AS hit_5_levels_milestone,
  COUNTIF(event_name = 'app_remove') > 0                            AS app_removed,
  ROUND(SUM(COALESCE(engagement_time_msec, 0)) / 1000.0, 1)         AS engagement_sec,
  -- Sessions: prefer ga_session_id if the SDK of this era populated it, else session_start count.
  COALESCE(NULLIF(COUNT(DISTINCT ga_session_id), 0),
           NULLIF(COUNTIF(event_name = 'session_start'), 0))         AS n_sessions,
  MIN(IF(is_active, event_ts_utc, NULL))                            AS first_active_ts_utc,
  MAX(IF(is_active, event_ts_utc, NULL))                            AS last_active_ts_utc,
  MAX(score)                                                        AS max_score,
  MAX(param_value)                                                  AS max_param_value
FROM `{{PROJECT}}.{{DATASET}}.events_clean`
GROUP BY user_pseudo_id, event_date;
