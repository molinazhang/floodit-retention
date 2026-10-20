# Resume bullets and interview explanation

**Rule:** bullets may only claim what the repository shows and numbers that appear in
`data/results/results.md` from executed queries. Pipeline executed 2026-10-19; the numbers
below are from that run.

## Bullets

* Built a reproducible BigQuery/SQL pipeline on Google's public Flood-It! event export
  (5.7 M events, 15.2 k app instances, 4.3 k new installs, 114 days): deduplicated event
  view, user-day table and new-user cohort table with nested-parameter extraction, window
  functions and clustered outputs; audited identifiers, duplicates, the timezone convention
  (UTC-7), the per-day event cap and seven anomalous export days before defining metrics.
* Showed that new users who completed 3+ levels on their first day returned on day 7 at
  8.9% vs 1.7% for users who never started a level (+7.1 pp, bootstrap 95% CI 5.3-9.1),
  replicated on held-out cohorts (+6.3 pp) and in 5 of 5 weekly cohort cells; translated the
  day-0 funnel drop into a single onboarding A/B test proposal with power analysis
  (8.7 k users/arm to detect 1 pp).

## Alternative phrasing if the ML component is worth the space

* Trained calibrated logistic and gradient-boosting models on day-0 behaviors to predict
  day-7 return (held-out AUC 0.65); permutation importance showed that first-session time span
  and engagement seconds, not level counts, carried the signal, which reframed the hand-made
  progress groups as a proxy for session length and shaped the experiment's mechanism metric.

## 60-second interview explanation (structure)

1. **Question and why it matters.** Day-7 retention is the metric a mobile game lives on;
   onboarding is the lever a product team controls. I asked which first-day behaviors
   separate users who come back on day 7, so the team can decide what to test next.
2. **Data and the unglamorous part.** Google's public Firebase export of Flood-It!, 114
   days, obfuscated, and, as the audit showed, capped at exactly 50,000 events per day.
   Before any metric I audited event names, duplicate bundles, the reporting-timezone day
   boundary (UTC-7), seven anomalous days with no `first_open`, and the difference between
   users with a real `first_open` and users merely first seen in the extract (72% of ids).
   That audit changed the cohort definition and the coverage rule.
3. **Method.** Exact-day D1/D7 retention with a foreground-activity definition; cohorts with
   incomplete follow-up or anomalous days excluded. Day-0 progress groups defined only from
   day-0 events. Exploratory/validation split by cohort date so the recommendation was
   checked on data it was not chosen on. Wilson intervals and bootstrap for uncertainty.
4. **Finding (one number).** "Users who completed 3+ levels on day 0 retained 7.1 pp better
   than users who never started a level (8.9% vs 1.7%); consistent on 5 of 5 weekly cells and
   on the held-out cohorts. Failing the first level cost nothing; never starting one did."
5. **What I did with it.** One specific onboarding change (auto-start the first level at first
   open instead of landing on the main menu), written up as an experiment with the unit of
   randomization, primary and guardrail metrics, and sample size. I'm explicit that the
   association is not causal and that the mechanical upper bound is about 1.3 pp; the test is
   how we would find out.
6. **If asked about ML.** A calibrated classifier on day-0 features as a check that my
   hand-made groups didn't miss a stronger signal. AUC was only 0.65 and the signal was
   session length, not level counts, which is itself informative: day-0 progress is mostly a
   marker of motivation, so the experiment is the only way to learn what onboarding can move.
