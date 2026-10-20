-- 03_event_params.sql
-- Purpose: which parameters each event carries, and which value slot is populated.
-- Demonstrates nested-field extraction (UNNEST of the event_params ARRAY<STRUCT>).
-- Output -> data/results/03_event_params.csv

SELECT
  e.event_name,
  p.key                                                         AS param_key,
  COUNT(*)                                                      AS n_rows,
  COUNTIF(p.value.string_value IS NOT NULL)                     AS n_string,
  COUNTIF(p.value.int_value    IS NOT NULL)                     AS n_int,
  COUNTIF(p.value.float_value  IS NOT NULL)                     AS n_float,
  COUNTIF(p.value.double_value IS NOT NULL)                     AS n_double,
  ANY_VALUE(p.value.string_value)                               AS example_string,
  MIN(p.value.int_value)                                        AS min_int,
  MAX(p.value.int_value)                                        AS max_int,
  APPROX_COUNT_DISTINCT(COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING))) AS approx_distinct_values
FROM `{{SOURCE_TABLE}}` AS e,
     UNNEST(e.event_params) AS p
WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
GROUP BY e.event_name, p.key
ORDER BY e.event_name, n_rows DESC;
