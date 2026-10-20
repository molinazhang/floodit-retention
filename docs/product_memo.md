# Product memo: Early engagement and seven-day retention in Flood-It!

**Status:** EXECUTED 2026-10-19. Every number below comes from `data/results/results.md` and
the CSVs produced by the queries in `data/results/query_log.csv` (BigQuery sandbox, no billing).

**To:** Product / Growth team · **From:** Jiajin Zhang · **Date:** 2026-10-19

## Question
Which early (day-0) behaviors are associated with a new user returning seven days later,
and what onboarding change should we test next?

## Bottom line
* Day-7 retention of new users is **5.4%** (Wilson 95% CI 4.7-6.2%); day-1 is **19.0%**
  (17.7-20.3%). Eligible cohort: 3,561 verified new installs, 2018-07-02 to 2018-09-26. Both
  rates are understated in absolute terms because the public export is capped at 50,000 events
  per day (see Limitations); the comparisons below are the point.
* **13.0%** of new users never start a level on day 0; **27.5%** start one but complete none.
  The day-0 funnel: 87% start a level, 59% complete one, 38% complete three, 26% complete five.
  The largest single drop is "started a level" to "completed one" (-28 pp of the cohort).
* Users who **complete 3+ levels** on day 0 return on day 7 at **8.9%** vs **1.7%** for users
  who never start a level: a **7.1 pp** gap (bootstrap 95% CI 5.3-9.1 pp). The ordering held in
  **5 of 5** week x platform cells with at least 30 users in both groups (all Android; no weekly
  iOS cell had 30 non-starters) and in the held-out validation cohorts (**+6.3 pp**, 7.3% vs
  1.0%, CI 4.1-8.3; exploratory half +8.4 pp, CI 4.7-12.1). Intermediate groups sit in between
  (started, none completed 3.0%; completed 1-2 levels 4.7%).
* **Failing the first level is not the problem.** Users whose first level ended in a fail
  return at **7.3%** (5.3-9.9), the same as users who completed it, **7.4%** (5.9-9.3); the
  bootstrap CI on the difference spans zero (-3.0 to +2.7 pp). The two low groups are users who
  **never started** a level (1.7%, 13.0% of the cohort) and users who started one but reached
  **no outcome** (2.5%, 11.4% of the cohort): a quarter of new installs with ~2% day-7 return.
* What the non-starters did: 434 of the 464 saw only the main menu, 72 reached the level-select
  screen, median foreground engagement 6.8 seconds, 83% gone within two minutes, 80% on Android.
  Among users who do start, the first level begins a median **2 seconds** after first open (89%
  within a minute), so the path is instant for those who take it; the main-menu fork is where a
  quarter of installs are lost.

## What this does and does not say
This is an observational association measured on one 2018 extract. Users who progress
further on day 0 are almost certainly more motivated to begin with. The secondary model
(`python/ml_day0_model.py`) makes this concrete: day-0 behaviors predict day-7 return only
weakly (held-out AUC 0.65 for both a logistic model and gradient boosting), and almost all of
that signal sits in *time spent in the first session* (active span, engagement seconds), not in
level counts. The progress groups are therefore largely a proxy for how long the first session
lasted. The 7.1 pp gap is an upper bound on what any onboarding change could achieve, not an
estimate of it; a mechanical upper bound for the proposed change is **about +1.3 pp** (if the
24.5% of users who never reach a first-level outcome retained like first-level completers).
Identifiers are per install, so reinstalls look like churn.

## Recommendation
Test **a shorter path to the first level: start the first level automatically at first open**,
replacing the main menu / mode-selection fork for new installs, with a one-line guided prompt
so that the level reaches an outcome (win, fail or reset all count; a fail does not hurt).
This is chosen over a guided, un-failable first level because the data show no retention
penalty for failing the first level, while never starting (or never finishing) one is where the
low-retention quarter of the cohort sits.

## Proposed experiment (details in docs/experiment_proposal.md)
Randomize new installs 50/50 at first open; primary metric = day-7 retention; guardrails =
day-0 uninstalls (Android), day-0 session length, ad/extra-steps usage, crashes. At baseline
5.4% and a minimum detectable lift of **1.0 pp** (alpha 0.05 two-sided, power 0.80), the test
needs **8,689 users per arm** (17,377 total). At this export's observed volume of ~39 eligible
new users per day that would take 444 days, which is why the live baseline and install volume
must be re-measured first: the export is a capped sample, and the real product's volume is
unknown from it. A 1.5 pp MDE needs 4,007 per arm; 2.0 pp needs 2,334.

## Limitations
* **Capped export.** Each daily table holds exactly 50,000 events (~470 users/day). Absolute
  retention is understated (a returning user can be missing from the day-7 table) and group
  gaps are biased upward if heavier players are more likely to be exported.
* Seven anomalous June days (2.5x normal user count, no `first_open`) were excluded with the
  cohorts whose day-0..7 window touches them (425 users); eligible cohorts start 2018-07-02.
* Retention drifted down over the summer (day-7: 7.3% in the July cohorts, 4.3% in
  August-September); the group ordering was stable, the levels were not.
* Obfuscated public dataset; `<Other>` placeholders limit country/version slicing, and
  acquisition channel is a placeholder on 75% of events, so channel mix could confound the
  association.
* Exact-day retention; the rolling variant (any active day in days 1-7) is 33% overall and
  ranks the groups identically (non-starters 21%, 3+ levels 49%).
* No causal identification; the secondary ML model is predictive only.
