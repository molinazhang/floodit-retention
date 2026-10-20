-- 11_events_clean.sql
-- Purpose: event-level analytical table. One row per deduplicated event inside the extract
-- window, with the nested parameters we use pulled into flat columns and each event classified.
-- Creates: {{PROJECT}}.{{DATASET}}.events_clean
--
-- Event-name lists verified against data/results/02_event_inventory.csv (audit run 2026-10-19):
-- all 37 names in the export are covered. Post-audit additions: `level_up` (35,666 events)
-- classified as gameplay, `select_content` (105,139 events; a user's mode choice) as foreground.

CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.events_clean`
-- No PARTITION BY event_date: BigQuery sandbox tables carry a 60-day partition expiration, which
-- deletes 2018 partitions at creation time (the first build produced an empty table). The table
-- is small (< 2 GB), so clustering alone is sufficient.
CLUSTER BY user_pseudo_id, event_name
AS
WITH raw AS (
  SELECT
    user_pseudo_id,
    user_id,
    PARSE_DATE('%Y%m%d', event_date)                      AS event_date,       -- reporting-timezone day
    TIMESTAMP_MICROS(event_timestamp)                     AS event_ts_utc,
    event_timestamp,
    event_bundle_sequence_id,
    event_name,
    platform,
    device.category                                       AS device_category,
    device.operating_system                               AS os,
    device.language                                       AS language,
    geo.country                                           AS country,
    app_info.version                                      AS app_version,
    traffic_source.source                                 AS traffic_source,
    traffic_source.medium                                 AS traffic_medium,
    TIMESTAMP_MICROS(user_first_touch_timestamp)          AS first_touch_ts_utc,
    -- Nested-parameter extraction. Each subquery returns NULL when the key is absent.
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'engagement_time_msec' LIMIT 1) AS engagement_time_msec,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id' LIMIT 1)        AS ga_session_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number' LIMIT 1)    AS ga_session_number,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'firebase_screen' LIMIT 1)      AS screen_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'level_name' LIMIT 1)           AS level_name,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
                               FROM UNNEST(event_params) WHERE key = 'value' LIMIT 1)                AS param_value,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
                               FROM UNNEST(event_params) WHERE key = 'score' LIMIT 1)                AS score,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'board' LIMIT 1)                AS board,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'virtual_currency_name' LIMIT 1) AS virtual_currency_name,
    TO_JSON_STRING(event_params)                          AS params_json
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
    AND user_pseudo_id IS NOT NULL AND user_pseudo_id != ''
),
dedup AS (
  -- Window function: keep one row per exact duplicate group (see 05_duplicates.sql).
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id, event_name, event_timestamp, event_bundle_sequence_id, params_json
      ORDER BY event_timestamp
    ) AS dup_rank
  FROM raw
),
classified AS (
  SELECT
    * EXCEPT (dup_rank, params_json),
    CASE
      WHEN event_name IN ('level_start_quickplay', 'level_start')       THEN 'level_start'
      WHEN event_name IN ('level_complete_quickplay', 'level_complete') THEN 'level_complete'
      WHEN event_name IN ('level_fail_quickplay', 'level_fail')         THEN 'level_fail'
      WHEN event_name IN ('level_reset_quickplay', 'level_reset')       THEN 'level_reset'
      WHEN event_name IN ('level_retry_quickplay', 'level_retry')       THEN 'level_retry'
      WHEN event_name IN ('level_end_quickplay', 'level_end')           THEN 'level_end'
      WHEN event_name = 'level_up'                                      THEN 'level_up'
      WHEN event_name = 'use_extra_steps'                               THEN 'extra_steps'
      WHEN event_name = 'no_more_extra_steps'                           THEN 'no_more_extra_steps'
      WHEN event_name = 'ad_reward'                                     THEN 'ad_reward'
      WHEN event_name = 'post_score'                                    THEN 'post_score'
      WHEN event_name IN ('spend_virtual_currency', 'earn_virtual_currency', 'in_app_purchase') THEN 'economy'
      WHEN event_name = 'completed_5_levels'                            THEN 'milestone_5_levels'
      WHEN event_name IN ('challenge_a_friend', 'challenge_accepted')   THEN 'social'
      WHEN event_name = 'first_open'                                    THEN 'first_open'
      WHEN event_name IN ('user_engagement', 'screen_view', 'session_start', 'select_content') THEN 'foreground'
      WHEN event_name IN ('app_remove', 'app_update', 'os_update', 'app_exception', 'app_clear_data',
                          'notification_receive', 'notification_dismiss', 'notification_foreground',
                          'notification_open', 'dynamic_link_first_open', 'firebase_campaign',
                          'error', 'app_store_subscription_convert', 'app_store_subscription_renew')
                                                                        THEN 'background_or_system'
      ELSE 'other'
    END AS event_class
  FROM dedup
  WHERE dup_rank = 1
)
SELECT
  *,
  -- Gameplay = the user did something inside the game.
  event_class IN ('level_start', 'level_complete', 'level_fail', 'level_reset', 'level_retry',
                  'level_end', 'level_up', 'extra_steps', 'no_more_extra_steps', 'ad_reward',
                  'post_score', 'economy', 'milestone_5_levels', 'social')  AS is_gameplay,
  -- Active = the app was in the foreground with the user present. Automatic background and
  -- system events (app_remove, os_update, ...) never count; user_engagement counts only with
  -- positive engagement time.
  (event_class IN ('level_start', 'level_complete', 'level_fail', 'level_reset', 'level_retry',
                   'level_end', 'level_up', 'extra_steps', 'no_more_extra_steps', 'ad_reward',
                   'post_score', 'economy', 'milestone_5_levels', 'social')
   OR event_name IN ('screen_view', 'session_start', 'select_content')   -- select_content = user tap (mode choice)
   OR (event_name = 'user_engagement' AND COALESCE(engagement_time_msec, 0) > 0))   AS is_active
FROM classified;
