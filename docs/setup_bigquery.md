# BigQuery setup (free sandbox, no billing)

The project only needs the BigQuery **sandbox**, which is free and does not require a credit
card. Sandbox limits that matter here: 1 TB of query processing per month, 10 GB of storage,
and tables expire after 60 days. The whole pipeline scans well under 100 GB in total
(see `data/results/query_log.csv` after a run), so the free tier is sufficient.

## One-time steps (you do these; they require your Google login)

1. Open https://console.cloud.google.com/bigquery while signed in to a Google account.
   If you have never used Google Cloud, the console offers to create a project and enables
   the sandbox automatically. Otherwise create a new project (any name, e.g.
   `floodit-retention`). **Do not enable billing.** The console shows a "Sandbox" badge.
2. Copy the **project ID** (not the display name) into `config/config.yaml` as `gcp_project`.
3. From the project root, create the virtualenv and install dependencies (already done if the
   `.venv` folder exists):

   ```bash
   python3 -m venv .venv && .venv/bin/pip install -r python/requirements.txt
   ```

4. First query run: `run_sql.py` opens a browser tab asking you to sign in and grant BigQuery
   access to the local script (pydata-google-auth). The token is cached under
   `~/.config/pydata/` so later runs do not prompt. If you prefer the gcloud CLI, run
   `gcloud auth application-default login` instead; the script uses Application Default
   Credentials when they exist.

## Execution order

```bash
source .venv/bin/activate
python python/run_sql.py --stage audit --dry-run   # cost estimates only
python python/run_sql.py --stage audit             # -> data/results/0*.csv
# Read the audit outputs (docs/data_quality_log.md has the checklist), then fix config.yaml and
# the event-name lists in sql/10_build/11_events_clean.sql if the inventory disagrees.
python python/run_sql.py --stage build             # creates 4 tables in <project>.floodit_retention
python python/run_sql.py --stage analysis          # -> data/results/2*.csv incl. 25_user_level.csv
python python/analysis.py                          # -> figures/*.png, data/results/summary_*.csv, data/results/results.md
python python/ml_day0_model.py                     # secondary: -> figures/ml_*.png, data/results/ml_metrics.json
python python/experiment_power.py                  # sample-size table for the proposal
```

## Sandbox gotchas met on the first run (already handled in the SQL)

* Sandbox tables carry a 60-day **partition** expiration as well as a 60-day table expiration,
  so a `PARTITION BY event_date` table built from 2018 data is empty the moment it is created.
  The derived tables are therefore clustered but not partitioned. If you re-add partitioning
  you must `DROP` the table first: BigQuery refuses to change a partitioning spec in place.
* `ARRAY_AGG(... IGNORE NULLS)` is not allowed as a window function.

## Verifying what was executed

Every query the runner executes is appended to `data/results/query_log.csv` with its dry-run
estimate and billed bytes. A results CSV without a matching log line was not produced by
this pipeline.
