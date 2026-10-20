# Analysis decisions (and why)

Recorded before the validation cohorts were examined. Each item names the alternative that
was considered.

1. **Exact-day ("classic") retention on day 1 and day 7**, calendar days in the export's
   reporting timezone. *Alternative:* rolling retention (returned on or after day 7) or
   24-hour windows from first open. Classic retention is what Firebase/GA4 dashboards show, so
   a product team can reconcile the numbers; rolling retention is carried as
   `active_days_d1_d7` for sensitivity.
2. **Active = foreground presence**, not "any event". Automatic events (`app_remove`,
   `os_update`, notification delivery) fire without the user and would inflate retention.
   `user_engagement` only counts with positive engagement time. A gameplay-only variant is
   reported alongside because it is stricter and closer to "played again".
3. **New user = `first_open` inside the extract, first observed that day, first-touch
   timestamp consistent.** Users merely first observed in the extract are excluded rather
   than treated as new; they bias early-progress features downward (they have already
   progressed before the extract began).
4. **Cohort window ends 7 days before the last extract day**, so every included user has an
   observable day 7. Partial follow-up cohorts are dropped, not imputed.
5. **Coverage check inside the window.** A cohort is excluded if any of its days 0..7 is a
   missing table or an anomalous day. *As written before the audit*, anomalous meant "distinct
   users below 60% of the trailing 7-day median" (partial export days would look like mass
   churn). *Revised after the audit (2026-10-19):* the export has no missing or low days but
   seven June days with 2.5x the normal user count and no `first_open` events, which the
   trailing median handled badly (it flagged two normal days and missed one anomaly). The rule
   now compares with the extract-wide median, is symmetric (< 60% or > 167%), and flags days
   with zero `first_open`. The revision was made from audit outputs only, before any retention
   figure was computed; it removes the 2018-06-12..06-29 cohorts (425 users).
6. **Behavior groups use day-0 events only** and are defined in SQL before outcomes are
   joined. The primary grouping is progress-based (none started / started none completed /
   completed 1-2 / completed 3+) because the funnel steps are directly actionable by
   onboarding; the cut at 3+ was chosen a priori as "past the first few levels" and is not
   tuned to retention. The secondary grouping (outcome of the very first level) isolates
   early difficulty.
7. **Temporal exploratory/validation split** (cohorts up to the config `exploratory_end`
   vs after). Groups and the recommendation are chosen on the exploratory half; the
   validation half is re-estimated with identical code. This is a replication check, not a
   causal identification strategy.
8. **Uncertainty:** Wilson intervals for rates; percentile bootstrap over users for
   differences; consistency reported as the share of week x platform cells in which the
   ordering holds (cells with >= 30 users in both groups).
9. **No adjustment model in the main analysis.** The day-0 features are descriptive
   associations; a regression "controlling for" engagement would still not identify the
   effect of progress on retention because both are driven by unobserved motivation. The
   secondary ML model is a predictive check, not an adjustment.
10. **Scan control:** every query filters `_TABLE_SUFFIX`, selects only needed columns, is
    dry-run first, and is refused above the configured byte limit. Derived tables are
    partitioned by date and clustered by user.
11. **The capped export is taken as given.** Every daily table holds exactly 50,000 events
    (`docs/data_quality_log.md`, section 0). No re-weighting is attempted because the sampling
    mechanism is undocumented; instead the memo states that absolute retention is understated
    and that group gaps are biased upward if heavier players are more likely to be exported.
    *Alternative considered:* restricting to users with many day-0 events to equalize
    inclusion probability, rejected because it would condition on the exposure of interest.
