-- 24_eligibility_summary.sql
-- Purpose: how many first_open users each eligibility rule removes, so exclusions are
-- reported, not hidden.
-- Output -> data/results/24_eligibility_summary.csv

SELECT 'all_users_with_first_open'              AS step, COUNT(*) AS n_users FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` UNION ALL
SELECT 'in_cohort_window',                               COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE in_cohort_window UNION ALL
SELECT '... and first_open_is_first_seen',               COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE in_cohort_window AND first_open_is_first_seen UNION ALL
SELECT '... and first_touch_consistent',                 COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE in_cohort_window AND first_open_is_first_seen AND first_touch_consistent UNION ALL
SELECT '... and complete_followup',                      COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE in_cohort_window AND first_open_is_first_seen AND first_touch_consistent AND complete_followup UNION ALL
SELECT '... and window_coverage_ok (= eligible)',        COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE eligible UNION ALL
SELECT 'eligible: exploratory phase',                    COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE eligible AND phase = 'exploratory' UNION ALL
SELECT 'eligible: validation phase',                     COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE eligible AND phase = 'validation' UNION ALL
SELECT 'eligible: users with >1 first_open date',        COUNT(*) FROM `{{PROJECT}}.{{DATASET}}.new_user_cohort` WHERE eligible AND n_first_open_dates > 1;
