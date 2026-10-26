# Day-0 behavior and day-7 retention in Flood-It!

Which first-day behaviors separate new users who come back on day 7 from those who don't, and
what should the product team test next. SQL on BigQuery, Python for the statistics, one
experiment proposal at the end.

**Data.** Google's public Flood-It! event export
(`firebase-public-project.analytics_153293282.events_*`): 114 daily tables of obfuscated
Firebase/GA4 events ending 2018-10-03
([docs](https://developers.google.com/analytics/bigquery/app-gaming-demo-dataset)). Google
says the fields are obfuscated and internal consistency "might be somewhat limited". The audit
stage measures how much.

## Results

Executed on a free BigQuery sandbox. Every query and its billed bytes are in
`data/results/query_log.csv` (about 11 GB scanned, re-runs included).

Eligible new users: 3,561, cohorts 2018-07-02 to 2018-09-26.

| Metric | Value |
|---|---|
| Day-7 retention | 5.4% (Wilson 95% CI 4.7-6.2%) |
| Day-1 retention | 19.0% |
| Day-7, completed 3+ levels on day 0 | 8.9% |
| Day-7, never started a level on day 0 | 1.7% |
| Gap | +7.1 pp (bootstrap 95% CI 5.3-9.1), +6.3 pp on held-out cohorts |
| Day-7, first level failed vs completed | 7.3% vs 7.4% |

Failing the first level is not associated with lower retention. Never starting a level 
is associated with lower rentention. A quarter of installs never reach a first-level outcome 
on day 0 and return at about 2%; most of them saw only the main menu. 
Recommendation: auto-start the first level at first open and test
it. The experiment needs 8,689 users per arm to detect a 1 pp lift. Details in
`docs/product_memo.md` and `docs/experiment_proposal.md`.

Figures: `figures/fig1_funnel.png`, `fig2_retention_by_cohort.png`, `fig3_behavior_groups.png`,
plus `ml_*.png` for the secondary model. Numbers: `data/results/results.md`.

## Caveats you should know before quoting anything

* The export is capped at 50,000 events per day (~470 users/day). Absolute retention
  is understated and group gaps are biased upward if heavier players are more likely to be
  exported. Only the comparisons mean anything.
* Seven June days were exported under a different regime (2.5x the users, no `first_open`).
  They and every cohort whose day-0..7 window touches them are excluded (425 users).
* Identifiers are per install. A reinstall is a new user and looks like churn.
* The association is observational. A secondary model (AUC 0.65) shows the signal is
  first-session length, not level counts; the progress groups are mostly a proxy for that.

## Reproducing the results

There are two options to reproduce the results.

**Python (You don't need a Google account).** The user-level export `data/results/25_user_level.csv`
(3,998 rows, one per new install) is committed. This regenerates the figures, `results.md`,
the model metrics and the power table:

```bash
python3 -m venv .venv && .venv/bin/pip install -r python/requirements.txt
.venv/bin/python python/analysis.py
.venv/bin/python python/ml_day0_model.py
.venv/bin/python python/experiment_power.py
```

**Full pipeline with free BigQuery sandbox (You will need a Google account).**
Create a sandbox project, put its id in `config/config.yaml`, then:

```bash
.venv/bin/python python/run_sql.py --stage audit --dry-run   # cost estimate only
.venv/bin/python python/run_sql.py --stage audit             # -> data/results/0*.csv
.venv/bin/python python/run_sql.py --stage build             # 4 tables in <project>.floodit_retention
.venv/bin/python python/run_sql.py --stage analysis          # -> data/results/2*.csv
```

then the three Python scripts above. The first run opens a browser tab for Google sign-in
(pydata-google-auth; token cached locally). Compare your `data/results/0*.csv` with the
committed ones; they should match row for row. `docs/setup_bigquery.md` has the details.

Things that break in the sandbox, already handled in the SQL: `PARTITION BY event_date` creates
an empty table because sandbox partitions older than 60 days expire at creation, so the derived
tables are clustered and not partitioned; `ARRAY_AGG(... IGNORE NULLS)` is rejected as a
window function. If you re-add partitioning you must `DROP` the table first.

`python/make_synthetic_data.py` makes a labeled synthetic dataset for smoke-testing with
`--synthetic`. Its outputs are git-ignored and are not results.

## Layout

```
config/config.yaml            project id, dataset, extract window, cohort window, exploratory/validation split
sql/00_audit/                 01 date coverage · 02 event inventory · 03 parameters · 04 identifiers & placeholders
                              05 duplicates · 06 coverage gaps · 07 first_open vs first-seen · 08 timezone check
sql/10_build/                 11 events_clean (dedup, nested-param extraction, event classes)
                              12 user_day (conditional aggregation) · 13 new_user_cohort (eligibility, D1/D7 outcomes)
                              14 cohort_day0_features (day-0 features, window functions, behavior groups)
sql/20_analysis/              21 retention by cohort · 22 funnel (GROUPING SETS) · 23 retention by behavior group
                              24 eligibility summary · 25 user-level export for Python
python/run_sql.py             runs SQL files in order; dry-run estimate, byte cap, CSV export, query log
python/analysis.py            Wilson CIs, bootstrap differences, consistency check, results.md, 3 figures
python/ml_day0_model.py       secondary predictive model, kept separate from the main analysis
python/experiment_power.py    sample-size table for the proposal
python/make_synthetic_data.py synthetic smoke-test generator
docs/metric_definitions.md    the metric contract: day convention, new user, active, D1/D7, groups
docs/analysis_decisions.md    each analytical choice and the alternative considered
docs/data_quality_log.md      what the audit found, with the measured values
docs/product_memo.md          finding, recommendation, experiment, limitations
docs/experiment_proposal.md   hypothesis, unit, treatment, metrics, guardrails, sample size
docs/results_and_recommendations.md  every result paired with the action it implies
docs/resume_bullets.md        two bullets and the interview explanation
```

## Method (Brief)

* Cohort = calendar day of a user's first `first_open` in the export's reporting timezone
  (UTC-7, measured in the audit). The user must not be seen earlier and the first-touch
  timestamp must agree. Users merely first observed in the extract are excluded and counted.
* Retention = at least one foreground event on exactly day 1 or day 7. Background events
  (`app_remove`, `os_update`, crashes) never count. Cohorts without a full 7-day follow-up, or
  with an anomalous day in the window, are excluded.
* Behavior groups use day-0 events only: progress (no level started / started none completed /
  completed 1-2 / completed 3+) and first-level outcome.
* Uncertainty: Wilson intervals, bootstrap CIs on differences, and a consistency check across
  weekly cohorts and platforms. Cohorts up to 2018-08-03 were used to choose the groups and the
  recommendation; later cohorts were re-estimated unchanged.
