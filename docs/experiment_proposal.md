# Experiment proposal: auto-start the first level at first open

> Numeric fields come from executed results (`data/results/results.md`,
> `data/results/experiment_power.csv`). The observational finding that motivates this proposal
> does **not** establish that the treatment will raise retention; that is what the experiment is
> for.

## Hypothesis
**H1.** Among new users, starting the first level automatically at first open (skipping the
main menu / mode-selection fork, with a one-line guided prompt so the level reaches an
outcome) increases day-7 retention relative to the current onboarding.
**Mechanism (from the observational analysis).** 24.5% of new installs never reach a
first-level outcome on day 0 (13.0% never start a level, 11.4% start one without a recorded
win/fail/reset) and return on day 7 at 1.7% and 2.5%; users whose first level reached any
outcome return at 5.4-7.4%, and a *failed* first level retains as well as a completed one
(7.3% vs 7.4%). Non-starters mostly saw only the main menu (434 of 464) and left within two
minutes, while users who do start do so a median 2 seconds after first open. If part of the gap
is caused by the early experience rather than by pre-existing motivation, removing the fork
should move some of that quarter across the threshold. Mechanical upper bound if all of them
retained like first-level completers: about +1.3 pp.

## Eligible users
New installs (`first_open`) on both platforms, excluding users whose first-touch timestamp
predates the install (reinstalls) and excluding test/internal devices. Users are enrolled at
first open, before any onboarding screen.

## Randomization
* **Unit:** user (`user_pseudo_id`), assigned at first open via a hashed id; sticky for the
  life of the install.
* **Allocation:** 50/50 control vs treatment. Stratify assignment by platform (80% of the
  non-starters in the export were on Android, so the platform-stratified read matters).
* **Exposure:** treatment can only take effect on day 0, so exposure = enrollment; no
  triggered-exposure dilution.

## Treatment vs control
* **Control:** current onboarding (first open lands on the main menu with a mode choice).
* **Treatment:** first open lands directly in the first level of the default mode, with a
  one-line guided prompt ("tap a color to flood the board") and the main menu reachable from
  the level. The level is *not* made un-failable: the data show no penalty for failing it. One
  change only, so a result is interpretable.

## Metrics
* **Primary:** day-7 retention (exact-day, active definition in docs/metric_definitions.md).
* **Secondary:** day-1 retention; share reaching a first-level outcome on day 0 (the mechanism
  check; 75.5% in the export); share completing >= 1 level on day 0 (59.4%); active days in
  days 1-7.
* **Guardrails:** day-0 uninstall rate on Android (`app_remove` within 24 h; 30% of eligible
  Android installs in the export); day-0 session length (an auto-started level that lengthens
  day 0 without changing return is a cost); ad-reward / extra-steps usage (monetization events
  must not drop); crash rate (`app_exception`).

## Sample size (from python/experiment_power.py)
Baseline day-7 retention 5.4%, alpha 0.05 two-sided, power 0.80, 50/50:

| absolute lift to detect | n per arm | total | days to enroll at the export's volume (39 eligible/day) | + 7 days observation |
|---|---|---|---|---|
| 1.0 pp (18.5% relative) | 8,689 | 17,377 | 444 | 451 |
| 1.5 pp (27.8% relative) | 4,007 | 8,015 | 205 | 212 |
| 2.0 pp (37.1% relative) | 2,334 | 4,668 | 119 | 126 |
| 3.0 pp (55.6% relative) | 1,106 | 2,213 | 57 | 64 |

The minimum detectable effect is chosen as **1.0 pp**, roughly 14% of the observed 7.1 pp gap
between the 3+-levels group and the non-starters and about three quarters of the 1.3 pp
mechanical upper bound, because a first-level change can at best move a fraction of users
across the threshold. The enrollment days in the table are computed from the public export's
volume, which is a capped sample (~39 eligible new installs per day); the live product's
install volume must be measured before committing to a duration, and a test that cannot reach
~8,700 users per arm in a few weeks should be run at a 1.5-2.0 pp MDE with the explicit
caveat that a true 1 pp effect would likely be missed.

## Observation period and analysis plan
* Enroll until 8,689 users per arm (re-measure the live baseline and daily volume first), then
  wait 7 days so the last enrolled user has a day 7.
* Analysis: two-proportion z-test on the primary metric with a pre-registered one-sided
  decision rule; difference reported with 95% CI; platform-stratified estimate as a
  consistency check; no peeking before the enrollment target is reached (or use a
  sequential test if the team wants earlier reads).
* **Decision rule:** ship if the lower bound of the CI on the day-7 lift is above 0 and no
  guardrail degrades beyond its pre-set threshold; iterate if the mechanism metric (share
  reaching a first-level outcome) moves but retention does not.

## Risks and limitations
* Novelty: an auto-started level can help first-week behavior without changing long-term
  retention; consider a day-14 follow-up read.
* Day-7 retention drifted from 7.3% (July 2018 cohorts) to 4.3% (August-September) in the
  export; a stratified or time-blocked analysis guards against a similar drift during the test.
* Spillover is negligible (single-player, per-install assignment).
* The historical data are from a capped 2018 export; the baseline must be re-measured in the
  live product.
