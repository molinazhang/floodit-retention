# Data quality log

Status legend: **[MEASURED]** = filled from `data/results/*.csv` produced by
`python python/run_sql.py --stage audit` on 2026-10-19 (BigQuery sandbox project
`floodit-retention`, dataset `floodit_retention`; every query is listed in
`data/results/query_log.csv`). Numbers below are the audit's, not the analysis's.

## 0. Headline: the export is capped at 50,000 events per day [MEASURED]
Every one of the 114 daily tables contains **exactly 50,000 events** (5,700,000 in total,
`01_tables_and_dates.csv`), so the export is a capped sample of the game's traffic, not the
full log. On a normal day the sample covers ~470 distinct users (median 471). The per-user-day
event distribution on normal days (from the built `user_day` table: mean 106 events, median 38,
10th percentile 6, only 6.9% of user-days with 3 or fewer events) looks like fairly complete
logs for the users who are present, rather than random thinning of events. The cap therefore
most plausibly limits *which users/bundles* appear on a given day. Consequences carried into
the analysis:
* A retained user can be absent from the day-7 table even though they played, so **absolute
  D1/D7 levels are understated** and are not comparable to dashboard figures for the game.
* Comparisons between day-0 behavior groups assume that a user's inclusion on later days does
  not depend on their day-0 behavior. If heavier players are more likely to be exported, the
  measured retention gap between high- and low-progress groups is **biased upward**. This is
  stated as a limitation in `docs/product_memo.md`.

## 1. Date coverage (`01_tables_and_dates.csv`) [MEASURED]
First table suffix: **20180612** · Last table suffix: **20181003** · Number of daily tables:
**114** (matches Google's documentation; `extract_start_suffix` and `cohort_start` in
config.yaml were already correct). Any `events_intraday_*` tables? **None** (the wildcard would
have listed them). Rows where `event_date != _TABLE_SUFFIX`: **0** on every day. Each table's
timestamps run from 07:00 UTC to ~07:01 UTC the next day (see section 8).

## 2. Event inventory (`02_event_inventory.csv`) [MEASURED]
37 distinct event names. All names the pipeline depends on exist (events / distinct users):
`first_open` 4,322 / 4,319 (present on 109 of 114 days, see section 6) ·
`user_engagement` 1,358,958 / 13,588 · `screen_view` 2,247,623 / 14,077 ·
`session_start` 74,353 / 12,261 · `level_start_quickplay` 523,430 / 10,166 ·
`level_complete_quickplay` 191,088 / 5,676 · `level_fail_quickplay` 137,035 / 6,343 ·
`level_reset_quickplay` 122,278 / 3,517 · `level_retry_quickplay` 29,939 / 2,940 ·
`level_end_quickplay` 349,729 / 8,168 · `use_extra_steps` 8,945 / 1,884 ·
`ad_reward` 1,912 / 354 · `post_score` 242,051 / 8,580 · `completed_5_levels` 1,867 / 1,597 ·
`spend_virtual_currency` 9,363 / 2,044 · `challenge_a_friend` 524 / 246 · `app_remove` 2,639 / 2,635.
The game has two modes: the `*_quickplay` events above and a progressive campaign with
`level_start` 74,417 · `level_end` 54,582 · `level_retry` 43,345 · `level_up` 35,666 ·
`level_complete` 33,986 · `level_fail` 17,353 · `level_reset` 8,535. Both modes are pooled in the
`event_class` CASE in `sql/10_build/11_events_clean.sql`.
**Changes made to the CASE after the audit:** `level_up` (35,666 events) was unclassified and is
now a gameplay class; `select_content` (105,139 events, the user's mode choice on the level-select
screen) was unclassified and now counts as a foreground/active event. Names listed in the CASE
that do not occur in this export (`earn_virtual_currency`, `notification_*`,
`app_store_subscription_*`) never match and are harmless. After the change only 19 events
(`dynamic_link_app_open`) fall into `other`.

## 3. Parameters (`03_event_params.csv`) [MEASURED]
* Level identity: progressive-mode events carry `level` (0-31, stored as INT64 on some rows and
  FLOAT64 on others) and `level_name` (e.g. `level_18`); quickplay events carry `board` (3 values)
  and, on `level_complete_quickplay`, `value` 13-49 (moves used).
* Score: `score` on `post_score` (0-21); `value` on `level_up` (1-44).
* Engagement time: `engagement_time_msec` on `user_engagement` (1,358,951 of 1,358,958 rows;
  max 5,243,585 ms).
* `ga_session_id` / `ga_session_number`: **absent** in this 2018 export, so `n_sessions` falls
  back to `session_start` counts (74,353 events over 12,261 users).
* `first_open` carries `previous_first_open_count` (0-85): a reinstall indicator; the
  eligibility rules in section 7 remove the cases where it matters.

## 4. Identifiers and placeholders (`04_identifiers_and_placeholders.csv`) [MEASURED]
`user_id` null share: **100%** (0 distinct values; the analysis uses `user_pseudo_id`, a
per-install identifier). Distinct `user_pseudo_id`: **15,175**. Users seen on >1 platform:
**0** · users with >1 `user_first_touch_timestamp`: **0** · events with null/empty pseudo id:
**0**. Platform: 53.2% Android / 46.8% iOS of events. Placeholder (`<Other>`/empty) shares:
country **0.09%** · app version **0%** · device category **0%** · operating system **5.9%** ·
traffic source **75.3%** (acquisition channel is unusable, as anticipated).

## 5. Duplicates (`05_duplicates.csv`) [MEASURED]
Exact-duplicate share is **<= 0.011%** for every event (highest: `spend_virtual_currency`
0.011%, `screen_view` 0.004%). `events_clean` keeps one row per exact duplicate group:
**191** rows removed (5,700,000 -> 5,699,809).

## 6. Coverage gaps and anomalous days (`06_coverage_gaps.csv`) [MEASURED]
Missing tables: **0**. Low-volume days: **0**. **Anomalous high-volume days: 7** -
2018-06-18, 06-19, 06-25, 06-26, 06-28, 06-30 and 07-01 - each with 1,187-1,283 distinct users
(2.5-2.7x the extract-wide median of 471) inside the same 50,000-event cap, a per-user-day
event median of 8 (vs 38 on normal days), and **no `first_open` at all** on five of them (10 and
1 on the other two). These days were exported under a different sampling regime; a cohort whose
day-7 falls on one of them would show inflated retention.
**Rule change after the audit:** the flag was originally "users < 60% of the trailing 7-day
median". With the anomaly days inside the trailing window that rule flagged two normal days
(07-02, 07-03) and missed 07-01. The rule now compares each day with the extract-wide median and
is symmetric (flag if < 60% or > 167% of the median), and also flags any day with zero
`first_open` events. The same rule is implemented in `sql/10_build/13_new_user_cohort.sql`
(`docs/analysis_decisions.md`, item 5). Effect: cohorts 2018-06-12 .. 2018-06-29 are excluded
(**425** users; the 06-30 and 07-01 cohorts have no members because no `first_open` was
exported). Eligible cohorts run from **2018-07-02 to 2018-09-26** (`24_eligibility_summary.csv`).

## 7. New vs merely-observed users (`07_first_open_vs_first_seen.csv`) [MEASURED]
Users without any `first_open` in the extract: **10,856** (share **71.5%** of 15,175). Of these,
9,074 have a first-touch timestamp before the extract (pre-existing installs) and 1,782 have a
first touch inside the extract but no exported `first_open` (consistent with the per-day cap in
section 0). Users with `first_open` on their first observed day (candidate new users): **4,307**
(2,974 with first-touch date equal to the first-open date, 1,333 within one day - the expected
UTC vs UTC-7 date shift for events between 00:00 and 07:00 UTC). Users whose `first_open` is
*not* on their first observed day: **12** (all with first touch before the extract: re-sent
`first_open` after a reinstall; excluded). Users with `first_open` on more than one date: **1**.
Eligibility funnel (`24_eligibility_summary.csv`): 4,319 first_open users -> 3,998 in the cohort
window (321 cohorts 09-27..10-03 lack a complete 7-day follow-up) -> 3,986 first_open is the
first seen day (-12) -> 3,986 first touch consistent (-0) -> **3,561 eligible** after the
coverage rule (-425): **1,256 exploratory** (cohorts <= 2018-08-03) and **2,305 validation**.

## 8. Timezone (`08_timezone_check.csv`) [MEASURED]
Events with UTC hours 0-6 (plus the first ~90 seconds of hour 7) carry an `event_date` one day
*earlier* than their UTC date; events from 07:00 UTC onward carry the same date. The reporting
day therefore begins at 07:00 UTC: implied reporting timezone offset **UTC-7**
(America/Los_Angeles on Pacific Daylight Time; the whole extract, June 12 - October 3, 2018,
lies inside PDT, so the offset is constant). The daily tables' timestamp ranges (07:00 UTC to
07:01 UTC next day) agree. Convention adopted: calendar days by `event_date`; see
`docs/metric_definitions.md`.

## Known limitations of the identifiers and obfuscation (apply regardless of results)
* `user_pseudo_id` is an app-instance id: one person with two devices is two users; a
  reinstall is a new user with a new `first_open`. Day-7 retention is therefore retention of
  an install, and uninstall-reinstall within 7 days looks like churn plus a new cohort member.
* Google states fields were obfuscated and internal consistency "might be somewhat limited";
  dimension values such as `<Other>` are placeholders and cannot be treated as a real
  category. Country/version breakdowns are only as good as the placeholder share allows.
* `traffic_source` is a placeholder on 75% of events; acquisition-channel effects
  (which could confound behavior-retention associations) cannot be adjusted for.
* `engagement_time_msec` is reported by the SDK in batches; day-0 engagement seconds is an
  approximation of foreground time, not an exact session length.
* The extract is a capped (50,000 events/day) 2018 snapshot of one game; absolute retention
  levels are not comparable to current products or to the game's own dashboards, only the
  internal comparisons are of interest.

## Fixes to the SQL needed to run in the sandbox (no analytical effect)
* `ARRAY_AGG(... IGNORE NULLS)` is not allowed as a window function in BigQuery; the coverage
  window was rewritten (and then replaced by the extract-wide rule above).
* Sandbox tables carry a 60-day partition expiration, so `PARTITION BY event_date` dropped
  every 2018 partition at creation time and the first build produced empty tables. The derived
  tables are now clustered but not partitioned (they are < 2 GB).
