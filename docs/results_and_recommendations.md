# Results and actionable recommendations (executed 2026-10-19)

Every number comes from `data/results/results.md`, the audit CSVs and `data/results/ml_metrics.json`.

## A. Data quality results (audit stage)

| # | Result | Recommendation |
|---|---|---|
| A1 | Every daily table holds exactly 50,000 events (5.7 M total, ~470 users/day): the export is a capped sample. | Report only internal comparisons; never quote absolute D1/D7 as the game's retention. State in every deliverable that levels are understated and group gaps may be biased upward. |
| A2 | Seven June days (06-18, 06-19, 06-25, 06-26, 06-28, 06-30, 07-01) have 2.5x the users and no `first_open`. | Keep the revised coverage rule (extract-wide median, symmetric, zero-first_open flag); exclude cohorts 06-12..06-29. Mention the revision as an audit-driven decision in interviews. |
| A3 | Reporting timezone is UTC-7 (day boundary 07:00 UTC); `event_date` agrees with table suffix on every row. | Keep calendar-day retention on `event_date`; no timestamp shifting needed. |
| A4 | 72% of pseudo-ids have no `first_open` in the extract; 12 users have `first_open` after first being seen; 1 user has two `first_open` dates. | Keep the strict new-user definition (first_open + first-seen + first-touch consistency). Do not treat "first seen" users as new. |
| A5 | `user_id` is 100% null; identifiers are per install; no user on two platforms. | Describe retention as retention of an install; list reinstalls as a known bias. |
| A6 | Traffic source is a placeholder on 75% of events; OS placeholder 6%; country and app version clean. | Do not attempt channel adjustment; country/version slices are allowed but secondary. |
| A7 | Exact duplicates <= 0.011% per event (191 rows removed). | Keep the dedup step; no further cleaning needed. |
| A8 | `ga_session_id` absent; `engagement_time_msec` present on 99.99% of `user_engagement` rows. | Keep `session_start` as the session fallback; use engagement seconds as the time-in-app measure. |
| A9 | `level_up` and `select_content` were unclassified in the event CASE. | Keep the new classes (gameplay, foreground). Re-check the inventory whenever the SQL is reused on another export. |
| A10 | Sandbox: partition expiration emptied date-partitioned tables; window `ARRAY_AGG(IGNORE NULLS)` rejected. | Keep tables clustered, not partitioned; DROP before changing a partitioning spec. |

## B. Funnel and retention results (analysis stage)

| # | Result | Recommendation |
|---|---|---|
| B1 | Day-7 retention 5.4% (4.7-6.2%), day-1 19.0% (17.7-20.3%); n = 3,561. | Use 5.4% only as the baseline for the power table; re-measure the live baseline before any experiment. |
| B2 | Day-0 funnel: 87% start a level, 59% complete one, 38% complete three, 26% complete five. Largest drop: started -> completed one (-28 pp). | Onboarding work should target getting the first level to an outcome, not later levels. |
| B3 | 13.0% never start a level; 27.5% start but complete none. | Treat these two groups (40% of installs) as the onboarding population; the proposed test targets the first. |
| B4 | Day-7 by progress group: A 1.7%, B 3.0%, C 4.7%, D 8.9%; D vs A +7.1 pp (5.3-9.1). | Use the monotone ordering as the headline association; present it as an upper bound, not an effect. |
| B5 | Ordering replicated: validation cohorts +6.3 pp (4.1-8.3), exploratory +8.4 pp; 5 of 5 week x platform cells (all Android; iOS cells too small). | Say "replicated on held-out cohorts and 5/5 weekly cells"; disclose that the cell check is Android-only. |
| B6 | First-level outcome: completed 7.4%, failed 7.3% (diff CI -3.0 to +2.7 pp), reset/retry 5.4%, started-no-outcome 2.5%, not started 1.7%. | Reject the "un-failable first level" option; choose "shorter path to the first level". |
| B7 | Non-starters: 434/464 saw only the main menu, 72 reached level select, median engagement 6.8 s, 83% gone within 2 min, 80% Android. | Treatment = auto-start the first level at first open, skipping the main-menu fork; stratify by platform. |
| B8 | Starters begin their first level a median 2 s after first open (89% within 60 s). | Do not frame the change as "faster"; frame it as removing the fork that a quarter of installs never cross. |
| B9 | Mechanical upper bound: moving the 24.5% without a first-level outcome to completer retention = +1.3 pp; moving non-starters alone to group D = +0.9 pp. | Power the test at 1.0 pp; be explicit that larger MDEs would miss any realistic effect. |
| B10 | Retention drifted down over the summer: D7 7.3% (July cohorts) -> 4.3% (Aug-Sep); D1 23% -> 17%. | Use time-blocked or stratified analysis in the experiment; never compare treatment and control enrolled in different weeks. |
| B11 | Rolling retention (any active day in d1-7) 33%; non-starters 21%, 3+ levels 49%: same ordering as exact-day. | Report rolling as the sensitivity check; the conclusion does not depend on the day convention. |
| B12 | Android day-0 uninstall: 30% of eligible installs; 28% in group A, 40% in B/C, 20% in D. | Add day-0 uninstall as a guardrail; watch for the auto-started level raising uninstalls among users who would have left from the menu anyway. |

## C. Secondary ML results

| # | Result | Recommendation |
|---|---|---|
| C1 | Held-out AUC 0.65 (logistic 0.649, gradient boosting 0.648); both roughly calibrated below 0.3 predicted probability. | Do not use the model as a targeting rule; it barely beats the base rate. Keep it as a sanity check. |
| C2 | Permutation importance: day-0 active span and engagement seconds carry almost all the signal; level counts contribute ~0. | Describe the progress groups as a proxy for first-session length. Add "share reaching a first-level outcome" and session length as mechanism metrics in the experiment. |
| C3 | The template's resume claim that "level completion, not time in app, carried the signal" is contradicted by the data. | Use the rewritten ML bullet in `docs/resume_bullets.md`; never state the original claim. |

## D. Experiment power results

| # | Result | Recommendation |
|---|---|---|
| D1 | At baseline 5.4%, alpha 0.05, power 0.80: 1.0 pp needs 8,689 per arm; 1.5 pp 4,007; 2.0 pp 2,334; 3.0 pp 1,106. | Plan for 8,689 per arm. |
| D2 | At the export's ~39 eligible new installs/day, 1.0 pp would take 444 days. | Measure the live install volume first; if it cannot reach ~8,700 per arm in a few weeks, run at 1.5-2.0 pp with the caveat that a true 1 pp effect would be missed. |
