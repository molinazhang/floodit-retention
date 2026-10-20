# Metric definitions

All definitions are implemented in `sql/10_build/*.sql`; this file is the human-readable
contract. Nothing in the analysis uses a definition that differs from the SQL.

## Day convention

* `event_date` in the export is the calendar day in the Firebase property's **reporting
  timezone**; `event_timestamp` is UTC. The analysis uses `event_date` for all day arithmetic
  (cohort day, day 1, day 7). `sql/00_audit/08_timezone_check.sql` recovers the implied offset:
  **measured UTC-7** (the reporting day starts at 07:00 UTC; America/Los_Angeles on Pacific
  Daylight Time, constant across the June-October 2018 extract). Details in
  `docs/data_quality_log.md`, section 8.
* "Day k" means exactly the calendar day `cohort_date + k`, not a 24-hour window from the
  first-open timestamp. This is the convention used by Firebase/GA4 retention reports and
  by most product teams; the trade-off is that a user who installs at 23:50 has a very short
  day 0.

## New user (cohort membership)

A user (`user_pseudo_id`) is a new user with `cohort_date = d` when all of the following hold:

1. The user has at least one `first_open` event in the extract, and `d` is the day of the
   earliest one.
2. No event for the user occurs on a day before `d` (`first_open_is_first_seen`).
3. `user_first_touch_timestamp`, when present, falls within one day of `d`
   (`first_touch_consistent`). This removes reinstalls and users whose first_open was re-sent.
4. `d + 7` is within the extract (`complete_followup`), so day-7 is observable.
5. No day in `d .. d+7` is flagged by the coverage check (`window_coverage_ok`): a missing
   table, a day whose distinct-user count is below 60% or above 167% of the extract-wide
   median, or a day with no `first_open` exported. The audit found seven anomalous
   high-volume days in June 2018 (`docs/data_quality_log.md`, section 6), so eligible cohorts
   run from 2018-07-02 to 2018-09-26.

Users merely *first observed* in the extract without a `first_open` event are **not** new
users; they are reported separately in `07_first_open_vs_first_seen.csv`.

## Active (meaningful activity)

An event counts as *active* when the app was in the foreground with the user present:

* any gameplay event (`level_*` including `level_up`, `use_extra_steps`, `ad_reward`,
  `post_score`, virtual currency, `completed_5_levels`, challenge events), or
* `screen_view`, `session_start` or `select_content` (the user's mode choice), or
* `user_engagement` with `engagement_time_msec > 0`.

Automatic background/system events never count: `app_remove`, `app_update`, `os_update`,
`app_exception`, `app_clear_data`, notification delivery events, `first_open` itself.

A stricter *gameplay-only* variant is carried alongside as a sensitivity check.

## Retention

* **Day-1 retention** = share of cohort users with >= 1 active event on `cohort_date + 1`.
* **Day-7 retention** = share of cohort users with >= 1 active event on `cohort_date + 7`.
* Denominator: eligible cohort users (all five conditions above). Exclusion counts are in
  `24_eligibility_summary.csv`.
* These are *classic* (exact-day) retention rates, not rolling ("returned on or after day 7")
  rates. The user-level export also carries `active_days_d1_d7` for rolling variants.

## Day-0 behavior groups

Computed from `cohort_date` events only (`sql/10_build/14_day0_features.sql`), so group
membership is fixed before the outcome window starts.

* **Progress group (`behavior_group`, primary)**
  * A: no level started on day 0
  * B: started >= 1 level, completed none
  * C: completed 1-2 levels
  * D: completed 3+ levels
* **First-level outcome group (`first_level_group`, secondary)**: not started / first level
  completed / first level failed / first level reset or retried / started without a recorded
  outcome.

The cut points (1-2 vs 3+) were fixed before retention was computed on validation cohorts;
`docs/analysis_decisions.md` records the reasoning.

## Exploratory vs validation cohorts

Cohorts up to `exploratory_end` (config) are used to choose group definitions and the
recommendation; cohorts after that date are held out and re-estimated with the same code and
no changes. A pattern that holds in both is reported as validated; one that holds only in
the exploratory half is reported as exploratory.
