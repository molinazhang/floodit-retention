-- 02_event_inventory.sql
-- Purpose: inventory of event names with volume, reach and date span. This decides which
-- progression events the funnel can use. Nothing downstream should reference an event that
-- is absent here.
-- Output -> data/results/02_event_inventory.csv

WITH e AS (
  SELECT event_name, event_date, user_pseudo_id, platform
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
)
SELECT
  event_name,
  COUNT(*)                                            AS n_events,
  COUNT(DISTINCT user_pseudo_id)                      AS n_users,
  ROUND(COUNT(*) / COUNT(DISTINCT user_pseudo_id), 2) AS events_per_user,
  MIN(event_date)                                     AS first_date,
  MAX(event_date)                                     AS last_date,
  COUNT(DISTINCT event_date)                          AS n_days_present,
  COUNTIF(platform = 'ANDROID')                       AS n_android,
  COUNTIF(platform = 'IOS')                           AS n_ios
FROM e
GROUP BY event_name
ORDER BY n_events DESC;
