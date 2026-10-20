#!/usr/bin/env python
"""
analysis.py - retention analysis, uncertainty estimates and the three main figures.

Input : data/results/25_user_level.csv  (one row per cohort user, produced by run_sql.py)
Output: figures/fig1_funnel.png, fig2_retention_by_cohort.png, fig3_behavior_groups.png
        data/results/summary_*.csv, data/results/results.md

    python python/analysis.py                 # real export
    python python/analysis.py --synthetic     # smoke test on labeled synthetic data

Statistical choices
* Rates: Wilson 95% intervals (better than Wald for small cells and rates near 0/1).
* Differences between behavior groups: percentile bootstrap over users (2,000 resamples),
  reference group = A (no level started on day 0).
* Exploratory vs validation: everything is estimated separately on the two temporal halves;
  group definitions were fixed in SQL before the validation half was examined.
"""
import argparse
import json
import pathlib

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

import viz_style as vs

ROOT = pathlib.Path(__file__).resolve().parents[1]
GROUP_ORDER = ["A_no_level_started", "B_started_none_completed", "C_completed_1_to_2", "D_completed_3_plus"]
GROUP_LABEL = {"A_no_level_started": "A: no level started", "B_started_none_completed": "B: started, none completed",
               "C_completed_1_to_2": "C: completed 1-2 levels", "D_completed_3_plus": "D: completed 3+ levels"}
FUNNEL_STEPS = [("first_open", "Opened app (first_open)", None),
                ("any_active", "Any active event", lambda d: d.d0_active_events > 0),
                ("started_level", "Started a level", lambda d: d.d0_levels_started >= 1),
                ("completed_1", "Completed 1+ level", lambda d: d.d0_levels_completed >= 1),
                ("completed_3", "Completed 3+ levels", lambda d: d.d0_levels_completed >= 3),
                ("completed_5", "Completed 5+ levels", lambda d: (d.d0_levels_completed >= 5) | d.d0_hit_5_levels.astype(bool))]


def rate_row(label, mask_or_df, col):
    d = mask_or_df
    k, n = int(d[col].sum()), int(len(d))
    p, lo, hi = vs.wilson(k, n)
    return {"segment": label, "n": n, f"{col}_k": k, col: p, f"{col}_lo": lo, f"{col}_hi": hi}


def boot_diff(a, b, n_boot, rng):
    """Percentile bootstrap CI for mean(b) - mean(a) over independent user resamples."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    if len(a) == 0 or len(b) == 0:
        return np.nan, np.nan, np.nan
    diffs = rng.choice(b, (n_boot, len(b))).mean(1) - rng.choice(a, (n_boot, len(a))).mean(1)
    return b.mean() - a.mean(), np.percentile(diffs, 2.5), np.percentile(diffs, 97.5)


def funnel_table(df):
    rows, prev = [], None
    for key, label, fn in FUNNEL_STEPS:
        n = len(df) if fn is None else int(fn(df).sum())
        rows.append({"step": key, "label": label, "n_users": n, "share_of_cohort": n / len(df),
                     "share_of_previous": (n / prev) if prev else 1.0})
        prev = n
    return pd.DataFrame(rows)


def fig_funnel(df, out, synthetic):
    ft = funnel_table(df)
    fig, ax = plt.subplots(figsize=(7.5, 4))
    y = np.arange(len(ft))[::-1]
    ax.barh(y, ft.share_of_cohort * 100, height=0.5, color=vs.ORDINAL_BLUE[:len(ft)], edgecolor=vs.SURFACE, linewidth=2)
    for yi, (_, r) in zip(y, ft.iterrows()):
        ax.text(r.share_of_cohort * 100 + 1, yi, f"{r.share_of_cohort:.0%}  (n={r.n_users:,})", va="center", fontsize=9, color=vs.TEXT)
    ax.set_yticks(y, ft.label)
    ax.set_xlim(0, 118)
    ax.set_xlabel("Share of eligible new users reaching the step on day 0 (%)")
    ax.grid(axis="y", visible=False)
    vs.finish(fig, ax, "Day-0 progression funnel", f"Eligible new users, n = {len(df):,}",
              "Source: Flood-It! public Firebase export, sql/20_analysis/22_funnel.sql and python/analysis.py", synthetic)
    fig.savefig(out)
    plt.close(fig)
    return ft


def fig_cohort(df, out, synthetic, exploratory_end):
    g = df.groupby("cohort_week")
    rows = []
    for wk, d in g:
        for col in ("retained_d1", "retained_d7"):
            p, lo, hi = vs.wilson(int(d[col].sum()), len(d))
            rows.append({"cohort_week": wk, "metric": col, "n": len(d), "rate": p, "lo": lo, "hi": hi})
    t = pd.DataFrame(rows)
    fig, ax = plt.subplots(figsize=(8.5, 4.2))
    for col, color, label in (("retained_d1", vs.SERIES["blue"], "Day-1 retention"), ("retained_d7", vs.SERIES["orange"], "Day-7 retention")):
        s = t[t.metric == col]
        ax.fill_between(s.cohort_week, s.lo * 100, s.hi * 100, color=color, alpha=0.15, linewidth=0)
        ax.plot(s.cohort_week, s.rate * 100, color=color, linewidth=2, marker="o", markersize=4, label=label)
        ax.text(s.cohort_week.iloc[-1], s.rate.iloc[-1] * 100, f"  {label} {s.rate.iloc[-1]:.1%}", va="center", fontsize=9, color=vs.TEXT)
    ax.axvline(pd.Timestamp(exploratory_end), color=vs.TEXT2, linewidth=1)
    ax.text(pd.Timestamp(exploratory_end), ax.get_ylim()[1], " exploratory | validation ", fontsize=8, color=vs.TEXT2, va="top", ha="center")
    ax.set_ylabel("Retention (%)")
    ax.set_xlabel("Weekly new-user cohort (Monday)")
    ax.set_ylim(bottom=0)
    ax.legend(loc="lower left", ncol=2, fontsize=9)
    ax.grid(axis="x", visible=False)
    ax.xaxis.set_major_locator(mdates.DayLocator(interval=14))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
    vs.finish(fig, ax, "Retention by weekly cohort", "Shaded band = Wilson 95% interval",
              "Source: sql/20_analysis/21_retention_by_cohort.sql and python/analysis.py", synthetic)
    fig.savefig(out)
    plt.close(fig)
    return t


def group_summary(df, group_col, order, n_boot, rng, ref):
    rows = []
    for phase in ("exploratory", "validation", "ALL"):
        d = df if phase == "ALL" else df[df.phase == phase]
        for plat in ("ALL", "ANDROID", "IOS"):
            dd = d if plat == "ALL" else d[d.platform == plat]
            if len(dd) == 0:
                continue
            base = dd[dd[group_col] == ref]
            for grp in order:
                s = dd[dd[group_col] == grp]
                if len(s) == 0:
                    continue
                p7, lo7, hi7 = vs.wilson(int(s.retained_d7.sum()), len(s))
                p1, lo1, hi1 = vs.wilson(int(s.retained_d1.sum()), len(s))
                diff, dlo, dhi = boot_diff(base.retained_d7, s.retained_d7, n_boot, rng) if grp != ref else (0.0, np.nan, np.nan)
                rows.append({"grouping": group_col, "phase": phase, "platform": plat, "group": grp, "n": len(s),
                             "share_of_users": len(s) / len(dd), "d1": p1, "d1_lo": lo1, "d1_hi": hi1,
                             "d7": p7, "d7_lo": lo7, "d7_hi": hi7,
                             "d7_diff_vs_ref": diff, "d7_diff_lo": dlo, "d7_diff_hi": dhi})
    return pd.DataFrame(rows)


def fig_groups(summ, out, synthetic):
    s = summ[(summ.platform == "ALL") & (summ.phase != "ALL") & (summ.grouping == "behavior_group")]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = np.arange(len(GROUP_ORDER))[::-1]
    offs = {"exploratory": 0.16, "validation": -0.16}
    colors = {"exploratory": vs.SERIES["blue"], "validation": vs.SERIES["orange"]}
    for phase in ("exploratory", "validation"):
        sp = s[s.phase == phase].set_index("group").reindex(GROUP_ORDER)
        yy = y + offs[phase]
        ax.hlines(yy, sp.d7_lo * 100, sp.d7_hi * 100, color=colors[phase], linewidth=2)
        ax.plot(sp.d7 * 100, yy, "o", color=colors[phase], markersize=8, markeredgecolor=vs.SURFACE, markeredgewidth=1.5,
                label=f"{phase} cohorts")
        for yi, (_, r) in zip(yy, sp.iterrows()):
            if pd.notna(r.d7):
                ax.text(r.d7_hi * 100 + 0.8, yi, f"{r.d7:.1%} (n={int(r.n):,})", va="center", fontsize=8, color=vs.TEXT2)
    ax.set_yticks(y, [GROUP_LABEL[g] for g in GROUP_ORDER])
    ax.set_xlabel("Day-7 retention (%), Wilson 95% interval")
    ax.set_xlim(left=0)
    ax.grid(axis="y", visible=False)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.16), ncol=2, fontsize=9)
    vs.finish(fig, ax, "Day-7 retention by day-0 progress group", "Groups use day-0 events only; validation cohorts were held out",
              "Source: sql/10_build/14_day0_features.sql, sql/20_analysis/23_retention_by_behavior_group.sql, python/analysis.py", synthetic, source_y=-0.1)
    fig.savefig(out)
    plt.close(fig)


def consistency(df, group_col, ref, top):
    """Share of weekly cohorts (and platforms) in which the top group out-retains the reference."""
    rows = []
    for (wk, plat), d in df.groupby(["cohort_week", "platform"]):
        a, b = d[d[group_col] == ref], d[d[group_col] == top]
        if len(a) >= 30 and len(b) >= 30:
            rows.append({"cohort_week": wk, "platform": plat, "n_ref": len(a), "n_top": len(b),
                         "d7_ref": a.retained_d7.mean(), "d7_top": b.retained_d7.mean(),
                         "top_higher": b.retained_d7.mean() > a.retained_d7.mean()})
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--n-boot", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=20261019)
    args = ap.parse_args()
    import yaml
    cfg = yaml.safe_load((ROOT / "config" / "config.yaml").read_text())
    if args.synthetic:
        src, figdir, resdir, tag = ROOT / "data/synthetic/synthetic_user_level.csv", ROOT / "figures_synthetic_smoke", ROOT / "data/synthetic", "SYNTHETIC "
    else:
        src, figdir, resdir, tag = ROOT / "data/results/25_user_level.csv", ROOT / "figures", ROOT / "data/results", ""
    if not src.exists():
        raise SystemExit(f"{src} not found. Run run_sql.py --stage analysis first (or make_synthetic_data.py for --synthetic).")
    figdir.mkdir(exist_ok=True)
    vs.apply()
    rng = np.random.default_rng(args.seed)
    raw = pd.read_csv(src, parse_dates=["cohort_date", "cohort_week"])
    for c in ("retained_d1", "retained_d7", "retained_d1_gameplay", "retained_d7_gameplay", "eligible", "d0_hit_5_levels",
              "first_open_is_first_seen", "first_touch_consistent", "complete_followup", "window_coverage_ok"):
        raw[c] = raw[c].astype(str).str.lower().isin(["true", "1", "1.0"])

    # Exclusions
    excl = pd.DataFrame([
        {"step": "users with first_open in cohort window", "n": len(raw)},
        {"step": "first_open is first observed day", "n": int(raw.first_open_is_first_seen.sum())},
        {"step": "+ first-touch timestamp consistent", "n": int((raw.first_open_is_first_seen & raw.first_touch_consistent).sum())},
        {"step": "+ complete 7-day follow-up", "n": int((raw.first_open_is_first_seen & raw.first_touch_consistent & raw.complete_followup).sum())},
        {"step": "+ no coverage gap in window (eligible)", "n": int(raw.eligible.sum())},
    ])
    excl.to_csv(resdir / "summary_exclusions.csv", index=False)
    df = raw[raw.eligible].copy()

    # Overall / phase / platform rates
    rows = []
    for col in ("retained_d1", "retained_d7", "retained_d7_gameplay"):
        rows.append(rate_row("ALL", df, col))
        for ph, d in df.groupby("phase"):
            rows.append(rate_row(f"phase={ph}", d, col))
        for pl, d in df.groupby("platform"):
            rows.append(rate_row(f"platform={pl}", d, col))
    overall = pd.DataFrame(rows)
    overall.to_csv(resdir / "summary_retention_overall.csv", index=False)

    ft = fig_funnel(df, figdir / "fig1_funnel.png", args.synthetic)
    ft.to_csv(resdir / "summary_funnel.csv", index=False)
    ct = fig_cohort(df, figdir / "fig2_retention_by_cohort.png", args.synthetic, cfg["exploratory_end"])
    ct.to_csv(resdir / "summary_retention_by_week.csv", index=False)

    g1 = group_summary(df, "behavior_group", GROUP_ORDER, args.n_boot, rng, "A_no_level_started")
    order2 = ["not_started", "first_level_completed", "first_level_failed", "first_level_reset_or_retry", "started_no_outcome"]
    g2 = group_summary(df, "first_level_group", order2, args.n_boot, rng, "first_level_completed")
    groups = pd.concat([g1, g2])
    groups.to_csv(resdir / "summary_behavior_groups.csv", index=False)
    fig_groups(groups, figdir / "fig3_behavior_groups.png", args.synthetic)
    cons = consistency(df, "behavior_group", "A_no_level_started", "D_completed_3_plus")
    cons.to_csv(resdir / "summary_consistency_by_week_platform.csv", index=False)

    # results.md
    head = {c: float(overall[(overall.segment == "ALL") & overall[c].notna()][c].iloc[0]) for c in ("retained_d1", "retained_d7")}
    g_all = g1[(g1.phase == "ALL") & (g1.platform == "ALL")].set_index("group")
    lines = [f"# {tag}Results (auto-generated by python/analysis.py)", "",
             ("**SYNTHETIC DATA - smoke test only. Nothing here is a finding.**" if args.synthetic else
              "Source: executed BigQuery queries listed in data/results/query_log.csv."), "",
             f"Eligible new users: {len(df):,} of {len(raw):,} first_open users in the cohort window "
             f"({df.cohort_date.min().date()} to {df.cohort_date.max().date()}).", "",
             "## Exclusions", excl.to_markdown(index=False), "",
             "## Retention (Wilson 95% CI)", "",
             "| metric | rate | 95% CI | n |", "|---|---|---|---|"]
    for _, r in overall[overall.segment.isin(["ALL", "phase=exploratory", "phase=validation", "platform=ANDROID", "platform=IOS"])].iterrows():
        col = [c for c in ("retained_d1", "retained_d7", "retained_d7_gameplay") if c in r and pd.notna(r[c])][0]
        lines.append(f"| {col} ({r.segment}) | {r[col]:.1%} | {r[col+'_lo']:.1%} - {r[col+'_hi']:.1%} | {int(r.n):,} |")
    lines += ["", "## Day-0 funnel", ft.assign(share_of_cohort=lambda t: (t.share_of_cohort * 100).round(1),
                                              share_of_previous=lambda t: (t.share_of_previous * 100).round(1)).to_markdown(index=False), "",
              "## Day-7 retention by day-0 progress group", ""]
    show = g1[g1.platform == "ALL"][["phase", "group", "n", "share_of_users", "d7", "d7_lo", "d7_hi", "d7_diff_vs_ref", "d7_diff_lo", "d7_diff_hi"]].copy()
    for c in ("share_of_users", "d7", "d7_lo", "d7_hi", "d7_diff_vs_ref", "d7_diff_lo", "d7_diff_hi"):
        show[c] = (show[c] * 100).round(1)
    lines += [show.to_markdown(index=False), "",
              "d7_diff_vs_ref = absolute percentage-point difference in day-7 retention vs group A, with percentile-bootstrap 95% CI.", "",
              "## Day-7 retention by first-level outcome group", ""]
    show2 = g2[(g2.platform == "ALL")][["phase", "group", "n", "d7", "d7_lo", "d7_hi"]].copy()
    for c in ("d7", "d7_lo", "d7_hi"):
        show2[c] = (show2[c] * 100).round(1)
    lines += [show2.to_markdown(index=False), "", "## Consistency check (D vs A, weekly cohorts x platform, cells with n>=30 each)", ""]
    if len(cons):
        lines.append(f"Group D out-retains group A in {int(cons.top_higher.sum())} of {len(cons)} week x platform cells.")
        lines.append(cons.groupby("platform").top_higher.agg(["sum", "count"]).rename(columns={"sum": "cells_D_higher", "count": "cells"}).to_markdown())
    else:
        lines.append("No week x platform cell had >= 30 users in both groups.")
    (resdir / "results.md").write_text("\n".join(lines) + "\n")
    json.dump({"n_eligible": int(len(df)), "n_raw": int(len(raw)), "synthetic": args.synthetic,
               "d1_retention": head["retained_d1"], "d7_retention": head["retained_d7"]},
              open(resdir / "summary_headline.json", "w"), indent=2, default=str)
    print(f"wrote {resdir/'results.md'} and figures in {figdir}")


if __name__ == "__main__":
    main()
