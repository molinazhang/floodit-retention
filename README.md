# Early Engagement and Seven-Day Retention in a Mobile Game

**Question.** Which early (first-day) behaviors are associated with new users returning seven
days later, and what onboarding change should the product team test next?

**Data.** Google's public Flood-It! mobile-game event export in BigQuery
(`firebase-public-project.analytics_153293282.events_*`): 114 days of obfuscated
Firebase/GA4 event data ending at `events_20181003`
([documentation](https://developers.google.com/analytics/bigquery/app-gaming-demo-dataset)).
Google warns that fields contain placeholder values and that internal consistency "might be
somewhat limited"; the audit stage measures how much that matters.

## Status: executed 2026-10-19

| Component | State |
|---|---|
| SQL audit, build and analysis queries (17 files) | **executed 2026-10-19** on a BigQuery sandbox project; every query and its billed bytes are in `data/results/query_log.csv` (about 11 GB scanned in total, including re-runs) |
| Query runner with dry-run cost estimates and logging | executed |
| Python analysis, uncertainty estimates, three figures | **executed on the real export**: `figures/fig1_funnel.png`, `fig2_retention_by_cohort.png`, `fig3_behavior_groups.png`; `data/results/results.md` |
| Secondary ML model (logistic + gradient boosting, calibration, importance, SHAP) | executed: `figures/ml_*.png`, `data/results/ml_metrics.json` |
| Experiment power calculator | executed: `data/results/experiment_power.csv` |
| Product memo, experiment proposal, resume bullets | **filled from the executed results** |

Headline results (eligible new users n = 3,561, cohorts 2018-07-02 to 2018-09-26): day-7 retention
5.4% (95% CI 4.7-6.2%), day-1 19.0%. Users who completed 3+ levels on day 0 returned on day 7
at 8.9% vs 1.7% for users who never started a level (+7.1 pp, bootstrap CI 5.3-9.1 pp),
replicated on held-out cohorts (+6.3 pp). Failing the first level does not affect retention;
however, never starting one did have implications for retention. 
Recommendation: auto-start the first level at first open.


## Reproducing the results
Two levels, depending on whether you want to touch BigQuery:
1. **Python stage only (no Google account needed).** The executed user-level export
   `data/results/25_user_level.csv` (3,998 rows, one per new install; obfuscated public data)
   is committed, so the figures, `results.md`, the model metrics and the power table can be
   regenerated using the code below:
   ```bash
   python3 -m venv .venv && .venv/bin/pip install -r python/requirements.txt
   .venv/bin/python python/analysis.py
   .venv/bin/python python/ml_day0_model.py
   .venv/bin/python python/experiment_power.py
   ```
   
2. **Full pipeline (free BigQuery sandbox, ~10 GB scanned).** Create a sandbox project, put its
   id in `config/config.yaml`, then follow "Setup and execution order" below. The audit CSVs
   in `data/results/0*.csv` and the query log let you check that a re-run matches.

`python/make_synthetic_data.py` generates a labeled synthetic dataset for smoke-testing the
code with `--synthetic`; its outputs are deliberately not committed and are never results.

## Layout

```
config/config.yaml            project id, dataset, extract window, cohort window, exploratory/validation split
sql/00_audit/                 01 date coverage · 02 event inventory · 03 parameters · 04 identifiers & placeholders
                              05 duplicates · 06 coverage gaps · 07 first_open vs first-seen · 08 timezone check
sql/10_build/                 11 events_clean (dedup + nested-param extraction + event classes; clustered, not partitioned)
                              12 user_day (conditional aggregation) · 13 new_user_cohort (eligibility + D1/D7 outcomes)
                              14 cohort_day0_features (day-0 only features, window functions, behavior groups)
sql/20_analysis/              21 retention by cohort · 22 funnel (GROUPING SETS) · 23 retention by behavior group
                              24 eligibility summary · 25 user-level export for Python
python/run_sql.py             runs SQL files in order; dry-run estimate, byte cap, CSV export, query log
python/analysis.py            Wilson CIs, bootstrap differences, consistency check, results.md, 3 figures
python/ml_day0_model.py       secondary predictive model (kept separate from the main analysis)
python/experiment_power.py    sample-size table for the proposal
python/make_synthetic_data.py SYNTHETIC smoke-test generator (clearly labeled)
docs/metric_definitions.md    the metric contract (day convention, new user, active, D1/D7, groups)
docs/analysis_decisions.md    each analytical choice and the alternative considered
docs/data_quality_log.md      audit checklist to fill from the audit CSVs
docs/product_memo.md          finding -> recommendation -> experiment -> limitations (template)
docs/experiment_proposal.md   hypothesis, unit, treatment, metrics, guardrails, sample size
docs/resume_bullets.md        two bullets + interview explanation (fill only from executed results)
```

## Setup and execution order

1. Create a BigQuery sandbox project and put its id in `config/config.yaml`
   (`docs/setup_bigquery.md`; no billing is needed).
2. `python3 -m venv .venv && .venv/bin/pip install -r python/requirements.txt`
3. Audit first, then read the outputs and correct the config and event-name lists:
   ```bash
   .venv/bin/python python/run_sql.py --stage audit --dry-run
   .venv/bin/python python/run_sql.py --stage audit
   ```
   Fill `docs/data_quality_log.md`. If `01_tables_and_dates.csv` shows a different first
   table, fix `extract_start_suffix`/`cohort_start`. If `02_event_inventory.csv` uses other
   progression event names, edit the `event_class` CASE in `sql/10_build/11_events_clean.sql`.
   (Done on 2026-10-19; the log records what was found.)
4. Build the tables and run the analysis queries:
   ```bash
   .venv/bin/python python/run_sql.py --stage build
   .venv/bin/python python/run_sql.py --stage analysis
   ```
5. Python analysis, then the secondary model and the power table:
   ```bash
   .venv/bin/python python/analysis.py
   .venv/bin/python python/ml_day0_model.py
   .venv/bin/python python/experiment_power.py
   ```
6. Fill the placeholder fields in `docs/product_memo.md`, `docs/experiment_proposal.md` and
   `docs/resume_bullets.md` from `data/results/results.md`, then choose the recommendation.

To smoke-test the code on synthetic data: `python python/make_synthetic_data.py` followed by
the three Python scripts with `--synthetic` (outputs go to `figures_synthetic_smoke/` and
`data/synthetic/`, which are git-ignored).

## Method in brief

* **Cohort** = calendar day of a user's first `first_open`, reporting-timezone days,
  requiring that the user was not seen earlier and that the first-touch timestamp agrees.
  Users merely first observed in the extract are excluded and counted.
* **Retention** = at least one *active* (foreground) event on exactly day 1 / day 7; automatic
  background events never count. Cohorts without a complete 7-day follow-up, or with a
  missing, low-volume or anomalous day inside the window, are excluded.
* **Early behavior groups** are built from day-0 events only: progress (no level started /
  started none completed / completed 1-2 / completed 3+) and first-level outcome.
* **Uncertainty**: Wilson 95% intervals, bootstrap CIs on group differences, and a
  consistency check across weekly cohorts and platforms. Cohorts are split by date into an
  exploratory half (used to choose groups and the recommendation) and a validation half
  (re-estimated unchanged).
* **Recommendation** is one onboarding change, written as an experiment proposal. The
  association is observational; the experiment is how it would be tested.

