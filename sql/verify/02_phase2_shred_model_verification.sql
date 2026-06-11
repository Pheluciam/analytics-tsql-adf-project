/* ============================================================================
   02_phase2_shred_model_verification.sql
   Phase 2 verification — ONE run, one PASS/FAIL grid covering every step:
   OPENJSON shred → staging → dimensions → fact MERGE → bridge → dates.
   Run AFTER all three procs:
       EXEC stg.load_jira_issue  @snapshot_label = N'snapshot_1';
       EXEC dm.merge_dimensions;
       EXEC dm.merge_fact_issue  @snapshot_label = N'snapshot_1';
   Expected baseline for snapshot_1: 19,339 issues (frozen Phase 1 parity).
   Result set 1 = the checks. Result sets 2-3 = eyeball samples.
   ============================================================================ */

WITH raw_keys AS
(
    -- Independent re-shred of raw: parity route that bypasses the load proc.
    SELECT DISTINCT j.issue_key
    FROM raw.jira_search_page AS p
    CROSS APPLY OPENJSON(p.page_json)
        WITH (issue_key NVARCHAR(20) N'$.key') AS j
    WHERE p.snapshot_label = N'snapshot_1'
),
m AS
(
    SELECT
        raw_distinct_keys  = (SELECT COUNT(*) FROM raw_keys),
        stg_rows           = (SELECT COUNT(*) FROM stg.jira_issue),
        stg_null_created   = (SELECT COUNT(*) FROM stg.jira_issue WHERE created_utc IS NULL),
        stg_null_id        = (SELECT COUNT(*) FROM stg.jira_issue WHERE issue_id IS NULL),
        stg_none_status    = (SELECT COUNT(*) FROM stg.jira_issue WHERE status_name = N'(none)'),
        stg_none_type      = (SELECT COUNT(*) FROM stg.jira_issue WHERE issuetype_name = N'(none)'),
        stg_pairs          = (SELECT COUNT(*) FROM stg.jira_issue_component),
        dim_status_rows    = (SELECT COUNT(*) FROM dm.dim_status),
        dim_priority_rows  = (SELECT COUNT(*) FROM dm.dim_priority),
        dim_issuetype_rows = (SELECT COUNT(*) FROM dm.dim_issuetype),
        dim_component_rows = (SELECT COUNT(*) FROM dm.dim_component),
        dim_date_rows      = (SELECT COUNT(*) FROM dm.dim_date),
        fact_rows          = (SELECT COUNT(*) FROM dm.fact_issue),
        fact_updated_rows  = (SELECT COUNT(*) FROM dm.fact_issue
                              WHERE last_updated_utc <> first_loaded_utc),
        fact_label_drift   = (SELECT COUNT(*) FROM dm.fact_issue
                              WHERE last_snapshot_label <> N'snapshot_1'),
        bridge_rows        = (SELECT COUNT(*) FROM dm.bridge_issue_component),
        resolved_drift     = (SELECT COUNT(*) FROM dm.fact_issue
                              WHERE (resolved_utc IS NULL AND resolved_date_key IS NOT NULL)
                                 OR (resolved_utc IS NOT NULL AND resolved_date_key IS NULL)),
        negative_cycles    = (SELECT COUNT(*) FROM dm.fact_issue WHERE cycle_days < 0),
        min_created_key    = (SELECT MIN(created_date_key) FROM dm.fact_issue),
        max_resolved_key   = (SELECT MAX(COALESCE(resolved_date_key, 0)) FROM dm.fact_issue)
)
SELECT check_id, check_name, detail, result
FROM m
CROSS APPLY (VALUES
    ( 1, N'staging parity vs raw (independent re-shred)',
      CONCAT(N'raw=', raw_distinct_keys, N' stg=', stg_rows),
      CASE WHEN raw_distinct_keys = stg_rows AND stg_rows = 19339
           THEN N'PASS' ELSE N'FAIL' END),
    ( 2, N'staging shred contract: no NULL created_utc / issue_id',
      CONCAT(N'null_created=', stg_null_created, N' null_id=', stg_null_id),
      CASE WHEN stg_null_created = 0 AND stg_null_id = 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 3, N'staging shred contract: no (none) status / issuetype',
      CONCAT(N'none_status=', stg_none_status, N' none_type=', stg_none_type),
      CASE WHEN stg_none_status = 0 AND stg_none_type = 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 4, N'component shred produced rows',
      CONCAT(N'pairs=', stg_pairs),
      CASE WHEN stg_pairs > 0 THEN N'PASS' ELSE N'FAIL' END),
    ( 5, N'all four data-driven dims populated',
      CONCAT(N'status=', dim_status_rows, N' priority=', dim_priority_rows,
             N' type=', dim_issuetype_rows, N' component=', dim_component_rows),
      CASE WHEN dim_status_rows > 0 AND dim_priority_rows > 0
            AND dim_issuetype_rows > 0 AND dim_component_rows > 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 6, N'dim_date fully populated 2015-2027',
      CONCAT(N'rows=', dim_date_rows, N' expected=4748'),
      CASE WHEN dim_date_rows = 4748 THEN N'PASS' ELSE N'FAIL' END),
    ( 7, N'fact parity: fact rows = staging rows',
      CONCAT(N'fact=', fact_rows, N' stg=', stg_rows),
      CASE WHEN fact_rows = stg_rows THEN N'PASS' ELSE N'FAIL' END),
    ( 8, N'fact audit: snapshot 1 is insert-only, labels clean',
      CONCAT(N'updated_rows=', fact_updated_rows, N' label_drift=', fact_label_drift),
      CASE WHEN fact_updated_rows = 0 AND fact_label_drift = 0
           THEN N'PASS' ELSE N'FAIL' END),
    ( 9, N'bridge parity: bridge rows = staging pairs',
      CONCAT(N'bridge=', bridge_rows, N' stg_pairs=', stg_pairs),
      CASE WHEN bridge_rows = stg_pairs THEN N'PASS' ELSE N'FAIL' END),
    (10, N'date integrity: resolved key<->utc consistent, no negative cycles',
      CONCAT(N'resolved_drift=', resolved_drift, N' negative_cycles=', negative_cycles),
      CASE WHEN resolved_drift = 0 AND negative_cycles = 0
           THEN N'PASS' ELSE N'FAIL' END),
    (11, N'date keys inside dim_date range',
      CONCAT(N'min_created=', min_created_key, N' max_resolved=', max_resolved_key),
      CASE WHEN min_created_key >= 20150101 AND max_resolved_key <= 20271231
           THEN N'PASS' ELSE N'FAIL' END)
) AS checks (check_id, check_name, detail, result)
ORDER BY check_id;

------------------------------------------------------------------------------
-- EYEBALL 1 — ten most recently created issues, fully joined across the star.
------------------------------------------------------------------------------
SELECT TOP (10)
    f.issue_key,
    t.issuetype_name,
    s.status_name,
    s.status_category,
    p.priority_name,
    f.resolution_name,
    f.created_utc,
    f.resolved_utc,
    f.cycle_days
FROM dm.fact_issue    AS f
JOIN dm.dim_status    AS s ON s.status_key    = f.status_key
JOIN dm.dim_priority  AS p ON p.priority_key  = f.priority_key
JOIN dm.dim_issuetype AS t ON t.issuetype_key = f.issuetype_key
ORDER BY f.created_utc DESC;

------------------------------------------------------------------------------
-- EYEBALL 2 — status-category mix (plausibility: mostly Done on 2015+ data).
------------------------------------------------------------------------------
SELECT
    s.status_category,
    issues = COUNT(*),
    pct    = CONVERT(DECIMAL(5, 1),
                     100.0 * COUNT(*) / SUM(COUNT(*)) OVER ())
FROM dm.fact_issue AS f
JOIN dm.dim_status AS s ON s.status_key = f.status_key
GROUP BY s.status_category
ORDER BY issues DESC;
