#!/usr/bin/env python
"""
experiment_power.py - sample-size table for the proposed onboarding A/B test.

Two-sided two-proportion z-test, 50/50 split, randomization unit = new user (user_pseudo_id).
Baseline day-7 retention and daily eligible new users are read from the analysis outputs when
present; override with --baseline and --daily-users.

    python python/experiment_power.py [--baseline 0.12 --daily-users 400 --mde 0.01 0.02 0.03]
"""
import argparse
import pathlib

import pandas as pd
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", type=float, help="control day-7 retention rate, e.g. 0.12")
    ap.add_argument("--daily-users", type=float, help="eligible new users per day entering the test")
    ap.add_argument("--mde", type=float, nargs="+", default=[0.01, 0.015, 0.02, 0.03], help="absolute lifts to detect")
    ap.add_argument("--alpha", type=float, default=0.05)
    ap.add_argument("--power", type=float, default=0.80)
    ap.add_argument("--synthetic", action="store_true")
    args = ap.parse_args()
    resdir = ROOT / ("data/synthetic" if args.synthetic else "data/results")
    baseline, daily = args.baseline, args.daily_users
    if baseline is None:
        s = pd.read_csv(resdir / "summary_retention_overall.csv")
        baseline = float(s[(s.segment == "ALL") & s.retained_d7.notna()].retained_d7.iloc[0])
    if daily is None:
        w = pd.read_csv(resdir / "summary_retention_by_week.csv")
        daily = float(w[w.metric == "retained_d7"].n.mean() / 7)
    rows = []
    for mde in args.mde:
        es = proportion_effectsize(baseline + mde, baseline)
        n_arm = NormalIndPower().solve_power(effect_size=es, alpha=args.alpha, power=args.power, ratio=1.0, alternative="two-sided")
        rows.append({"baseline_d7": baseline, "mde_abs": mde, "mde_rel": mde / baseline, "n_per_arm": int(round(n_arm)),
                     "n_total": int(round(2 * n_arm)), "days_to_enrol_at_observed_volume": round(2 * n_arm / daily, 1),
                     "days_incl_7d_observation": round(2 * n_arm / daily + 7, 1)})
    t = pd.DataFrame(rows)
    t.to_csv(resdir / "experiment_power.csv", index=False)
    print(f"baseline d7 = {baseline:.4f}, eligible new users/day = {daily:.1f}, alpha={args.alpha}, power={args.power}")
    print(t.to_string(index=False))


if __name__ == "__main__":
    main()
