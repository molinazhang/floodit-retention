-- 04_identifiers_and_placeholders.sql
-- Purpose: how usable are the identifiers, and how much obfuscation ("<Other>", NULL, '')
-- sits in the dimensions we might segment by.
-- Output -> data/results/04_identifiers_and_placeholders.csv

WITH e AS (
  SELECT *
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
)
SELECT 'n_events'                              AS metric, COUNT(*)                                                     AS value FROM e UNION ALL
SELECT 'n_distinct_user_pseudo_id',               COUNT(DISTINCT user_pseudo_id)                                        FROM e UNION ALL
SELECT 'n_distinct_user_id',                      COUNT(DISTINCT user_id)                                               FROM e UNION ALL
SELECT 'share_events_user_id_null',               ROUND(COUNTIF(user_id IS NULL) / COUNT(*), 4)                         FROM e UNION ALL
SELECT 'share_events_pseudo_id_null_or_empty',    ROUND(COUNTIF(user_pseudo_id IS NULL OR user_pseudo_id = '') / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_events_first_touch_null',           ROUND(COUNTIF(user_first_touch_timestamp IS NULL) / COUNT(*), 4)      FROM e UNION ALL
SELECT 'share_events_platform_android',           ROUND(COUNTIF(platform = 'ANDROID') / COUNT(*), 4)                    FROM e UNION ALL
SELECT 'share_events_platform_ios',               ROUND(COUNTIF(platform = 'IOS') / COUNT(*), 4)                        FROM e UNION ALL
SELECT 'share_events_platform_other',             ROUND(COUNTIF(platform NOT IN ('ANDROID','IOS') OR platform IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_country_placeholder',               ROUND(COUNTIF(geo.country IN ('<Other>', '') OR geo.country IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_device_category_placeholder',       ROUND(COUNTIF(device.category IN ('<Other>', '') OR device.category IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_os_placeholder',                    ROUND(COUNTIF(device.operating_system IN ('<Other>', '') OR device.operating_system IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_app_version_placeholder',           ROUND(COUNTIF(app_info.version IN ('<Other>', '') OR app_info.version IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'share_traffic_source_placeholder',        ROUND(COUNTIF(traffic_source.source IN ('<Other>', '(direct)', '') OR traffic_source.source IS NULL) / COUNT(*), 4) FROM e UNION ALL
SELECT 'n_users_multiple_platforms',              COUNT(*) FROM (SELECT user_pseudo_id FROM e GROUP BY 1 HAVING COUNT(DISTINCT platform) > 1) UNION ALL
SELECT 'n_users_multiple_first_touch_values',     COUNT(*) FROM (SELECT user_pseudo_id FROM e GROUP BY 1 HAVING COUNT(DISTINCT user_first_touch_timestamp) > 1)
ORDER BY metric;
