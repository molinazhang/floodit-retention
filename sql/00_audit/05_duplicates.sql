-- 05_duplicates.sql
-- Purpose: quantify exact duplicate event rows. Firebase exports can contain re-sent bundles;
-- the build step removes rows that match on every field below (keeping one).
-- Output -> data/results/05_duplicates.csv

WITH keyed AS (
  SELECT
    event_name,
    COUNT(*) AS n_rows,
    COUNT(*) - COUNT(DISTINCT CONCAT(
        COALESCE(user_pseudo_id, ''), '|', event_name, '|', CAST(event_timestamp AS STRING), '|',
        CAST(COALESCE(event_bundle_sequence_id, -1) AS STRING), '|', TO_JSON_STRING(event_params)
    )) AS n_exact_duplicates,
    -- Looser key: same user, event, timestamp (ignores params/bundle); shows near-duplicates.
    COUNT(*) - COUNT(DISTINCT CONCAT(
        COALESCE(user_pseudo_id, ''), '|', event_name, '|', CAST(event_timestamp AS STRING)
    )) AS n_same_user_event_ts
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
  GROUP BY event_name
)
SELECT
  event_name, n_rows, n_exact_duplicates,
  ROUND(n_exact_duplicates / n_rows, 5) AS share_exact_duplicates,
  n_same_user_event_ts,
  ROUND(n_same_user_event_ts / n_rows, 5) AS share_same_user_event_ts
FROM keyed
ORDER BY n_rows DESC;
