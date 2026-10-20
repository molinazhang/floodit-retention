#!/usr/bin/env python
"""
ml_day0_model.py - SECONDARY analysis: how well do day-0 behaviors predict day-7 return?

This is deliberately separate from the main retention comparison. Its job is (1) to check
that the hand-built behavior groups are not missing a stronger day-0 signal, and (2) to give
a calibrated probability that could later define an "at-risk on day 0" targeting rule. It is
NOT a causal model and does not estimate the effect of any intervention.

Design
* Temporal split: train on exploratory cohorts, evaluate on validation cohorts (same split as
  the main analysis), so evaluation mirrors "fit on the past, score the future".
* Models: L2 logistic regression (standardized inputs; interpretable coefficients) and a
  shallow histogram gradient-boosting classifier (non-linearities, interactions).
* Metrics on validation cohorts: AUC, average precision, log loss, Brier score, vs. a
  prevalence-only baseline. Calibration curve with 10 quantile bins.
* Importance: permutation importance (AUC drop) on validation; SHAP summary for the GBM
  when the shap package is available.

    python python/ml_day0_model.py [--synthetic]
"""
import argparse
import json
import pathlib

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.calibration import calibration_curve
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, log_loss, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

import viz_style as vs

ROOT = pathlib.Path(__file__).resolve().parents[1]
NUM = ["d0_active_events", "d0_gameplay_events", "d0_engagement_sec", "d0_sessions", "d0_levels_started",
       "d0_levels_completed", "d0_levels_failed", "d0_levels_reset", "d0_levels_retried", "d0_extra_steps",
       "d0_no_more_extra_steps", "d0_ad_rewards", "d0_post_scores", "d0_economy_events", "d0_social_events",
       "d0_active_span_sec", "d0_secs_to_first_level", "first_open_hour_utc"]
CAT = ["platform", "d0_first_level_outcome"]


def build_X(df):
    X = df[NUM].copy().astype(float)
    X["d0_secs_to_first_level_missing"] = X.d0_secs_to_first_level.isna().astype(float)
    X["d0_secs_to_first_level"] = X.d0_secs_to_first_level.fillna(X.d0_secs_to_first_level.max() if X.d0_secs_to_first_level.notna().any() else 0)
    X["d0_active_span_sec"] = X.d0_active_span_sec.fillna(0)
    for c in NUM:
        if c.startswith("d0_") and c not in ("d0_secs_to_first_level",):
            X[c] = np.log1p(X[c].clip(lower=0))  # heavy-tailed counts
    X = pd.concat([X, pd.get_dummies(df[CAT].astype(str), prefix=CAT, dtype=float)], axis=1)
    return X


def metrics(y, p):
    return {"auc": roc_auc_score(y, p), "avg_precision": average_precision_score(y, p),
            "log_loss": log_loss(y, p), "brier": brier_score_loss(y, p)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    if args.synthetic:
        src, figdir, resdir = ROOT / "data/synthetic/synthetic_user_level.csv", ROOT / "figures_synthetic_smoke", ROOT / "data/synthetic"
    else:
        src, figdir, resdir = ROOT / "data/results/25_user_level.csv", ROOT / "figures", ROOT / "data/results"
    vs.apply()
    df = pd.read_csv(src)
    for c in ("retained_d7", "eligible"):
        df[c] = df[c].astype(str).str.lower().isin(["true", "1", "1.0"])
    df = df[df.eligible].reset_index(drop=True)
    X = build_X(df)
    y = df.retained_d7.astype(int).values
    tr, te = (df.phase == "exploratory").values, (df.phase == "validation").values
    Xtr, Xte = X[tr].reindex(columns=X.columns, fill_value=0), X[te].reindex(columns=X.columns, fill_value=0)

    lr = make_pipeline(StandardScaler(), LogisticRegression(C=0.5, max_iter=2000))
    gbm = HistGradientBoostingClassifier(max_depth=3, learning_rate=0.05, max_iter=400, early_stopping=True,
                                         validation_fraction=0.15, random_state=args.seed)
    lr.fit(Xtr, y[tr]); gbm.fit(Xtr, y[tr])
    p_lr, p_gbm = lr.predict_proba(Xte)[:, 1], gbm.predict_proba(Xte)[:, 1]
    base = np.full(te.sum(), y[tr].mean())
    out = {"n_train": int(tr.sum()), "n_valid": int(te.sum()), "prevalence_train": float(y[tr].mean()),
           "prevalence_valid": float(y[te].mean()), "synthetic": args.synthetic,
           "baseline_prevalence": {"log_loss": log_loss(y[te], base), "brier": brier_score_loss(y[te], base)},
           "logistic_l2": metrics(y[te], p_lr), "hist_gradient_boosting": metrics(y[te], p_gbm)}

    # Coefficients (standardized) for the logistic model
    coef = pd.DataFrame({"feature": X.columns, "std_coef": lr[-1].coef_[0]}).sort_values("std_coef", key=abs, ascending=False)
    coef.to_csv(resdir / "ml_logistic_coefficients.csv", index=False)

    # Permutation importance on validation (GBM)
    pi = permutation_importance(gbm, Xte, y[te], scoring="roc_auc", n_repeats=10, random_state=args.seed, n_jobs=1)
    imp = pd.DataFrame({"feature": X.columns, "auc_drop_mean": pi.importances_mean, "auc_drop_std": pi.importances_std}).sort_values("auc_drop_mean", ascending=False)
    imp.to_csv(resdir / "ml_permutation_importance.csv", index=False)

    # Figure: calibration
    fig, ax = plt.subplots(figsize=(5.2, 5))
    curves = []
    for p, color, label in ((p_lr, vs.SERIES["blue"], "Logistic (L2)"), (p_gbm, vs.SERIES["orange"], "Gradient boosting")):
        fy, fx = calibration_curve(y[te], p, n_bins=10, strategy="quantile")
        curves.append((fx, fy, color, label))
    # Axis range follows the data: with a ~5% base rate every point sits far below 1.0, and a
    # fixed 0-1 frame would squash the curves into one corner.
    lim = max(max(fx.max(), fy.max()) for fx, fy, _, _ in curves) * 1.15
    ax.plot([0, lim], [0, lim], color=vs.GRID, linewidth=1, label="perfect calibration")
    for fx, fy, color, label in curves:
        ax.plot(fx, fy, marker="o", markersize=6, linewidth=2, color=color, label=label, markeredgecolor=vs.SURFACE)
    ax.set_xlim(0, lim); ax.set_ylim(0, lim)
    ax.set_xlabel("Predicted probability of day-7 return"); ax.set_ylabel("Observed share returning on day 7")
    ax.legend(loc="upper left", fontsize=9)
    vs.finish(fig, ax, "Calibration on validation cohorts", f"n = {te.sum():,} held-out users; AUC LR {out['logistic_l2']['auc']:.3f}, GBM {out['hist_gradient_boosting']['auc']:.3f}",
              "Secondary analysis: python/ml_day0_model.py", args.synthetic)
    fig.savefig(figdir / "ml_calibration.png"); plt.close(fig)

    # Figure: importance
    top = imp.head(12).iloc[::-1]
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.barh(top.feature, top.auc_drop_mean, xerr=top.auc_drop_std, height=0.5, color=vs.SERIES["blue"], ecolor=vs.TEXT2, capsize=2)
    ax.set_xlabel("Permutation importance (mean AUC drop on validation, 10 repeats)")
    ax.grid(axis="y", visible=False)
    vs.finish(fig, ax, "Which day-0 features carry the signal?", "Gradient-boosting model; importance measured on held-out cohorts",
              "Secondary analysis: python/ml_day0_model.py", args.synthetic)
    fig.savefig(figdir / "ml_feature_importance.png"); plt.close(fig)

    try:
        import shap
        ex = shap.TreeExplainer(gbm)
        samp = Xte.sample(min(3000, len(Xte)), random_state=args.seed)
        sv = ex.shap_values(samp)
        sv = sv[1] if isinstance(sv, list) else sv
        plt.figure(figsize=(7, 5))
        shap.summary_plot(sv, samp, show=False, max_display=12, color_bar=True)
        plt.gcf().set_facecolor(vs.SURFACE)
        plt.title("SHAP summary (validation sample)" + ("  [SYNTHETIC]" if args.synthetic else ""), loc="left")
        plt.savefig(figdir / "ml_shap_summary.png"); plt.close()
        out["shap"] = "ok"
    except Exception as e:  # shap is optional
        out["shap"] = f"skipped: {type(e).__name__}: {e}"

    json.dump(out, open(resdir / "ml_metrics.json", "w"), indent=2)
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
