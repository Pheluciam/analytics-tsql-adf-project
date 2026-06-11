/* ============================================================================
   03_phase3_views_merge_verification.sql
   Phase 3 verification — ONE run, one PASS/FAIL grid covering the snapshot_2
   MERGE upsert and the pbi presentation-view contracts.
   Run AFTER:
       ADF pl_ingest_jira_snapshot (snapshot_label = snapshot_2)
       EXEC stg.load_jira_issue  @snapshot_label = N'snapshot_2';
       EXEC dm.merge_dimensions;
       EXEC dm.merge_fact_issue  @snapshot_label = N'snapshot_2';
   Counts are derived dynamically (suite stays valid for any later snapshot);
   only the frozen snapshot_1 baselines (40 raw pages, 19,339 issues) are
   hardcoded. Result set 1 = the checks. Result sets 2-3 = eyeball samples
   (portal renders only the last result set — highlight + Run a section, M2-7).
   ============================================================================ */

WITH raw_s2_keys AS
(
    -- Independent re-shred of the snapshot_2 raw pages: parity route that
    -- bypasses the load proc entirely.
    SELECT DISTINCT j.issue_key
    FROM raw.jira_search_page AS p
    CROSS APPLY OPENJSON(p.page_json)
        WITH (issue_key NVARCHAR(20) N'$.key') AS j
    WHERE p.snapshot_label = N'snapshot_2'
),
m AS
(
    SELECT
        raw_labels         = (SELECT COUNT(DISTINCT snapshot_label) FROM raw.jira_search_page),
        raw_s1_pages       = (SELECT COUNT(*) FROM raw.jira_search_page
                              WHERE snapshot_label = N'snapshot_1'),
        raw_s2_pages       = (SELECT COUNT(*) FROM raw.jira_search_page
                              WHERE snapshot_label = N'snapshot_2'),
        raw_s2_keys        = (SELECT COUNT(*) FROM raw_s2_keys),
        stg_labels         = (SELECT COUNT(DISTINCT snapshot_label) FROM stg.jira_issue),
        stg_s2_rows        = (SELECT COUNT(*) FROM stg.jira_issue
                              WHERE snapshot_label = N'snapshot_2'),
        stg_rows           = (SELECT COUNT(*) FROM stg.jira_issue),
        stg_pairs          = (SELECT COUNT(*) FROM stg.jira_issue_component),
        fact_rows          = (SELECT COUNT(*) FROM dm.fact_issue),
        fact_updated_rows  = (SELECT COUNT(*) FROM dm.fact_issue
                              WHERE last_updated_utc <> first_loaded_utc),
        fact_audit_drift   = (SELECT COUNT(*) FROM dm.fact_issue
                              WHERE last_updated_utc <> first_loaded_utc
                                AND last_snapshot_label <> N'snapshot_2'),
        bridge_rows        = (SELECT COUNT(*) FROM dm.bridge_issue_component),
        componentless      = (SELECT COUNT(*) FROM dm.fact_issue AS f
                              WHERE NOT EXISTS (SELECT 1 FROM dm.bridge_issue_component AS b
                                                WHERE b.issue_key = f.issue_key)),
        v_backlog_rows     = (SELECT COUNT(*) FROM pbi.vw_backlog_flow),
        v_resolution_rows  = (SELECT COUNT(*) FROM pbi.vw_resolution_performance),
        v_mix_rows         = (SELECT COUNT(*) FROM pbi.vw_priority_component_mix),
        v_date_rows        = (SELECT COUNT(*) FROM pbi.vw_dim_date),
        dim_date_rows      = (SELECT COUNT(*) FROM dm.dim_date),
        v_backlog_open     = (SELECT SUM(is_open) FROM pbi.vw_backlog_flow),
        v_resolution_open  = (SELECT SUM(is_open) FROM pbi.vw_resolution_performance),
        v_cycle_age_drift  = (SELECT COUNT(*) FROM pbi.vw_resolution_performance
                              WHERE (is_open = 1 AND (age_days IS NULL OR cycle_days IS NOT NULL))
                                 OR (is_open = 0 AND (age_days IS NOT NULL OR cycle_days IS NULL))),
        v_negative_age     = (SELECT COUNT(*) FROM pbi.vw_resolution_performance
                              WHERE age_days < 0),
        v_mix_null_comp    = (SELECT COUNT(*) FROM pbi.vw_priority_component_mix
                              WHERE component_name IS NULL)
)
SELECT check_id, check_name, detail, result
FROM m
CROSS APPLY (VALUES
    ( 1, N'raw holds both snapshots, snapshot_1 frozen at 40 pages',
      CONCAT(N'labels=', raw_labels, N' s1_pages=', raw_s1_pages, N' s2_pages=', raw_s2_pages),
      CASE WHEN raw_labels = 2 AND raw_s1_pages = 40 AND raw_s2_pages > 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 2, N'staging truncate-reload contract: snapshot_2 only',
      CONCAT(N'labels=', stg_labels, N' s2_rows=', stg_s2_rows, N' total=', stg_rows),
      CASE WHEN stg_labels = 1 AND stg_s2_rows = stg_rows AND stg_rows > 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 3, N'staging parity vs raw snapshot_2 (independent re-shred)',
      CONCAT(N'raw=', raw_s2_keys, N' stg=', stg_rows),
      CASE WHEN raw_s2_keys = stg_rows THEN N'PASS' ELSE N'FAIL' END),
    ( 4, N'fact parity: fact rows = staging rows, never below 19,339 baseline',
      CONCAT(N'fact=', fact_rows, N' stg=', stg_rows),
      CASE WHEN fact_rows = stg_rows AND fact_rows >= 19339
           THEN N'PASS' ELSE N'FAIL' END),
    ( 5, N'merge audit: updates exist and all carry snapshot_2 label',
      CONCAT(N'updated=', fact_updated_rows, N' label_drift=', fact_audit_drift),
      CASE WHEN fact_updated_rows > 0 AND fact_audit_drift = 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 6, N'bridge parity: bridge rows = staging pairs',
      CONCAT(N'bridge=', bridge_rows, N' stg_pairs=', stg_pairs),
      CASE WHEN bridge_rows = stg_pairs THEN N'PASS' ELSE N'FAIL' END),
    ( 7, N'issue-grain views match fact row count',
      CONCAT(N'backlog=', v_backlog_rows, N' resolution=', v_resolution_rows, N' fact=', fact_rows),
      CASE WHEN v_backlog_rows = fact_rows AND v_resolution_rows = fact_rows
           THEN N'PASS' ELSE N'FAIL' END),
    ( 8, N'mix view grain: bridge pairs + componentless issues, no NULL component',
      CONCAT(N'mix=', v_mix_rows, N' expected=', bridge_rows + componentless,
             N' null_comp=', v_mix_null_comp),
      CASE WHEN v_mix_rows = bridge_rows + componentless AND v_mix_null_comp = 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 9, N'open-issue definition consistent across views',
      CONCAT(N'backlog_open=', v_backlog_open, N' resolution_open=', v_resolution_open),
      CASE WHEN v_backlog_open = v_resolution_open THEN N'PASS' ELSE N'FAIL' END),
    (10, N'resolution view: cycle/age mutually exclusive, no negative age',
      CONCAT(N'drift=', v_cycle_age_drift, N' negative_age=', v_negative_age),
      CASE WHEN v_cycle_age_drift = 0 AND v_negative_age = 0
           THEN N'PASS' ELSE N'FAIL' END),
    (11, N'date passthrough complete',
      CONCAT(N'view=', v_date_rows, N' dim=', dim_date_rows),
      CASE WHEN v_date_rows = dim_date_rows THEN N'PASS' ELSE N'FAIL' END)
) AS checks (check_id, check_name, detail, result)
ORDER BY check_id;

------------------------------------------------------------------------------
-- EYEBALL 1 — the issues snapshot_2 touched: the MERGE story, row by row.
-- New issues: first_loaded = last_updated. Updated: last_updated moved on.
------------------------------------------------------------------------------
SELECT
    f.issue_key,
    f.first_loaded_utc,
    f.last_updated_utc,
    f.last_snapshot_label,
    change_type = CASE WHEN f.last_updated_utc = f.first_loaded_utc
                       THEN N'INSERT (new issue)'
                       ELSE N'UPDATE (changed)' END
FROM dm.fact_issue AS f
WHERE f.last_snapshot_label = N'snapshot_2'
ORDER BY change_type, f.issue_key;

------------------------------------------------------------------------------
-- EYEBALL 2 — backlog flow plausibility from the page-1 view: last 6 months
-- of inflow vs outflow (counts by month, straight off the view).
------------------------------------------------------------------------------
SELECT
    month_label = COALESCE(ci.month_label, co.month_label),
    inflow      = COALESCE(ci.inflow, 0),
    outflow     = COALESCE(co.outflow, 0)
FROM (
    SELECT month_label = CONVERT(NCHAR(7), created_date, 23), inflow = COUNT(*)
    FROM pbi.vw_backlog_flow
    WHERE created_date >= DATEADD(MONTH, -6, CONVERT(DATE, SYSUTCDATETIME()))
    GROUP BY CONVERT(NCHAR(7), created_date, 23)
) AS ci
FULL OUTER JOIN (
    SELECT month_label = CONVERT(NCHAR(7), resolved_date, 23), outflow = COUNT(*)
    FROM pbi.vw_backlog_flow
    WHERE resolved_date >= DATEADD(MONTH, -6, CONVERT(DATE, SYSUTCDATETIME()))
    GROUP BY CONVERT(NCHAR(7), resolved_date, 23)
) AS co
  ON co.month_label = ci.month_label
ORDER BY month_label;
