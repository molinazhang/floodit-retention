#!/usr/bin/env python
"""
run_sql.py - execute the project's SQL files against BigQuery, in order, with cost control.

Usage (from the project root, with the virtualenv active):
    python python/run_sql.py --stage audit --dry-run      # estimate bytes only, runs nothing
    python python/run_sql.py --stage audit                # run audit queries -> data/results/*.csv
    python python/run_sql.py --stage build                # create tables in your sandbox dataset
    python python/run_sql.py --stage analysis             # run analysis queries -> CSVs
    python python/run_sql.py --file sql/00_audit/02_event_inventory.sql

Placeholders replaced in every SQL file:
    {{PROJECT}} {{DATASET}} {{SOURCE_TABLE}} {{START_SUFFIX}} {{END_SUFFIX}}
    {{COHORT_START}} {{COHORT_END}} {{EXPLORATORY_END}}

Authentication (no gcloud CLI needed): the first run opens a browser window for Google
sign-in via pydata-google-auth and caches the token locally. If Application Default
Credentials already exist (gcloud), they are used instead. Never put secrets in config.yaml.

Cost control: every query is dry-run first; its estimated bytes are logged to
data/results/query_log.csv and the query is refused if it exceeds max_bytes_per_query.
"""
import argparse
import csv
import datetime as dt
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "config.yaml"
RESULTS = ROOT / "data" / "results"
STAGES = {
    "audit": ROOT / "sql" / "00_audit",
    "build": ROOT / "sql" / "10_build",
    "analysis": ROOT / "sql" / "20_analysis",
}
SCOPES = ["https://www.googleapis.com/auth/bigquery", "https://www.googleapis.com/auth/cloud-platform"]


def load_config():
    cfg = yaml.safe_load(CONFIG.read_text())
    if cfg["gcp_project"] in ("", "YOUR_SANDBOX_PROJECT_ID"):
        sys.exit("Set gcp_project in config/config.yaml to your BigQuery sandbox project id first "
                 "(see docs/setup_bigquery.md).")
    return cfg


def render(sql_text, cfg):
    repl = {
        "{{PROJECT}}": cfg["gcp_project"],
        "{{DATASET}}": cfg["dataset"],
        "{{SOURCE_TABLE}}": cfg["source_table"],
        "{{START_SUFFIX}}": cfg["extract_start_suffix"],
        "{{END_SUFFIX}}": cfg["extract_end_suffix"],
        "{{COHORT_START}}": cfg["cohort_start"],
        "{{COHORT_END}}": cfg["cohort_end"],
        "{{EXPLORATORY_END}}": cfg["exploratory_end"],
    }
    for k, v in repl.items():
        sql_text = sql_text.replace(k, str(v))
    return sql_text


def get_client(project):
    from google.cloud import bigquery
    try:
        import google.auth
        creds, _ = google.auth.default(scopes=SCOPES)
    except Exception:
        import pydata_google_auth
        creds = pydata_google_auth.get_user_credentials(SCOPES, use_local_webserver=True)
    return bigquery.Client(project=project, credentials=creds)


def ensure_dataset(client, project, dataset):
    from google.cloud import bigquery
    from google.api_core.exceptions import NotFound
    ref = bigquery.DatasetReference(project, dataset)
    try:
        client.get_dataset(ref)
    except NotFound:
        ds = bigquery.Dataset(ref)
        ds.location = "US"  # the public dataset lives in US; tables must share the location
        client.create_dataset(ds)
        print(f"created dataset {project}.{dataset} (US)")


def log_query(name, est_bytes, actual_bytes, status):
    RESULTS.mkdir(parents=True, exist_ok=True)
    path = RESULTS / "query_log.csv"
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["run_at_utc", "sql_file", "estimated_bytes", "estimated_gb", "actual_bytes", "status"])
        w.writerow([dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), name,
                    est_bytes, round((est_bytes or 0) / 1e9, 3), actual_bytes, status])


def run_file(client, path, cfg, dry_run_only):
    from google.cloud import bigquery
    sql = render(path.read_text(), cfg)
    name = path.name
    est = client.query(sql, job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False))
    est_bytes = est.total_bytes_processed or 0
    print(f"{name}: estimated {est_bytes/1e9:.3f} GB")
    if est_bytes > cfg["max_bytes_per_query"]:
        log_query(name, est_bytes, None, "REFUSED_over_max_bytes")
        print(f"  refused: exceeds max_bytes_per_query={cfg['max_bytes_per_query']}")
        return
    if dry_run_only:
        log_query(name, est_bytes, None, "dry_run")
        return
    job = client.query(sql)
    result = job.result()
    actual = job.total_bytes_processed
    if job.statement_type and job.statement_type.startswith("CREATE"):
        log_query(name, est_bytes, actual, "ok_ddl")
        print(f"  created {job.destination}")
        return
    df = result.to_dataframe()
    out = RESULTS / (path.stem + ".csv")
    df.to_csv(out, index=False)
    log_query(name, est_bytes, actual, f"ok_rows={len(df)}")
    print(f"  wrote {out.relative_to(ROOT)} ({len(df)} rows, {actual/1e9:.3f} GB billed)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", choices=STAGES.keys())
    ap.add_argument("--file", action="append", help="specific SQL file(s) to run")
    ap.add_argument("--dry-run", action="store_true", help="estimate bytes only")
    args = ap.parse_args()
    if not args.stage and not args.file:
        ap.error("give --stage or --file")
    cfg = load_config()
    files = []
    if args.stage:
        files += sorted(STAGES[args.stage].glob("*.sql"))
    if args.file:
        files += [ROOT / f for f in args.file]
    client = get_client(cfg["gcp_project"])
    if not args.dry_run and (args.stage in ("build", "analysis") or args.file):
        ensure_dataset(client, cfg["gcp_project"], cfg["dataset"])
    for f in files:
        run_file(client, f, cfg, args.dry_run)


if __name__ == "__main__":
    main()
