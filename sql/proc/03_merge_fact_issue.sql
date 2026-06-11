/* ============================================================================
   03_merge_fact_issue.sql
   dm.merge_fact_issue — MERGE upsert of the issue fact from staging, plus
   delete-and-insert refresh of the component bridge. The lead-theme core:
   snapshot 2 (Phase 3) re-runs this and the OUTPUT $action counts become
   the before/after upsert evidence.
   MERGE guardrails per forward-verify M2-P2-3: HOLDLOCK target, key-only ON
   (PK seek), single-writer ETL pattern, XACT_ABORT + explicit transaction.
   No WHEN NOT MATCHED BY SOURCE: issues never leave the locked JQL window,
   and a partial source must never delete facts.
   Walkthrough: TSQL_MODEL.md (repo root).
   ============================================================================ */

CREATE OR ALTER PROCEDURE dm.merge_fact_issue
    @snapshot_label NVARCHAR(30)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- Pre-flight 1: staging loaded, and for the labelled snapshot.
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM stg.jira_issue
                       WHERE snapshot_label = @snapshot_label)
        BEGIN
            ;THROW 50021, N'dm.merge_fact_issue: stg.jira_issue holds no rows for the requested snapshot_label — run stg.load_jira_issue first.', 1;
        END;

        ------------------------------------------------------------------
        -- Pre-flight 2: every staging attribute must resolve to a dim row,
        -- or the INNER JOINs below would silently drop issues. Fail loudly
        -- instead — this defends the proc run order.
        ------------------------------------------------------------------
        IF EXISTS (SELECT 1 FROM stg.jira_issue AS i
                   LEFT JOIN dm.dim_status    AS s ON s.status_name    = i.status_name
                   LEFT JOIN dm.dim_priority  AS p ON p.priority_name  = i.priority_name
                   LEFT JOIN dm.dim_issuetype AS t ON t.issuetype_name = i.issuetype_name
                   WHERE s.status_key IS NULL
                      OR p.priority_key IS NULL
                      OR t.issuetype_key IS NULL)
        BEGIN
            ;THROW 50022, N'dm.merge_fact_issue: staging attributes missing from dimensions — run dm.merge_dimensions first.', 1;
        END;

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- Fact upsert. Source resolves surrogate keys + date keys up front
        -- so the ON clause stays key-only (target PK seek). The MATCHED
        -- branch fires only on real change (IS DISTINCT FROM is NULL-safe),
        -- keeping last_updated_utc an honest change marker.
        ------------------------------------------------------------------
        DECLARE @actions TABLE (merge_action NVARCHAR(10) NOT NULL);

        MERGE dm.fact_issue WITH (HOLDLOCK) AS tgt
        USING (
            SELECT
                i.issue_key,
                i.issue_id,
                i.summary,
                s.status_key,
                p.priority_key,
                t.issuetype_key,
                i.resolution_name,
                created_date_key  = CONVERT(INT, CONVERT(CHAR(8), i.created_utc,  112)),
                resolved_date_key = CONVERT(INT, CONVERT(CHAR(8), i.resolved_utc, 112)),
                i.created_utc,
                i.updated_utc,
                i.resolved_utc
            FROM stg.jira_issue    AS i
            JOIN dm.dim_status     AS s ON s.status_name    = i.status_name
            JOIN dm.dim_priority   AS p ON p.priority_name  = i.priority_name
            JOIN dm.dim_issuetype  AS t ON t.issuetype_name = i.issuetype_name
            WHERE i.snapshot_label = @snapshot_label
        ) AS src
           ON tgt.issue_key = src.issue_key
        WHEN MATCHED AND
             (   tgt.status_key        IS DISTINCT FROM src.status_key
              OR tgt.priority_key      IS DISTINCT FROM src.priority_key
              OR tgt.issuetype_key     IS DISTINCT FROM src.issuetype_key
              OR tgt.resolution_name   IS DISTINCT FROM src.resolution_name
              OR tgt.resolved_date_key IS DISTINCT FROM src.resolved_date_key
              OR tgt.updated_utc       IS DISTINCT FROM src.updated_utc
              OR tgt.resolved_utc      IS DISTINCT FROM src.resolved_utc
              OR tgt.summary           IS DISTINCT FROM src.summary)
            THEN UPDATE SET
                 tgt.summary             = src.summary,
                 tgt.status_key          = src.status_key,
                 tgt.priority_key        = src.priority_key,
                 tgt.issuetype_key       = src.issuetype_key,
                 tgt.resolution_name     = src.resolution_name,
                 tgt.resolved_date_key   = src.resolved_date_key,
                 tgt.updated_utc         = src.updated_utc,
                 tgt.resolved_utc        = src.resolved_utc,
                 tgt.last_updated_utc    = SYSUTCDATETIME(),
                 tgt.last_snapshot_label = @snapshot_label
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (issue_key, issue_id, summary,
                         status_key, priority_key, issuetype_key, resolution_name,
                         created_date_key, resolved_date_key,
                         created_utc, updated_utc, resolved_utc,
                         last_snapshot_label)
                 VALUES (src.issue_key, src.issue_id, src.summary,
                         src.status_key, src.priority_key, src.issuetype_key,
                         src.resolution_name,
                         src.created_date_key, src.resolved_date_key,
                         src.created_utc, src.updated_utc, src.resolved_utc,
                         @snapshot_label)
        OUTPUT $action INTO @actions (merge_action);

        ------------------------------------------------------------------
        -- Bridge refresh: components are a full multi-valued set per issue,
        -- so MERGE semantics don't fit — delete-and-insert scoped to the
        -- issues in this load is the professional pattern.
        ------------------------------------------------------------------
        DELETE b
        FROM dm.bridge_issue_component AS b
        WHERE EXISTS (SELECT 1 FROM stg.jira_issue AS i
                      WHERE i.issue_key = b.issue_key);

        INSERT INTO dm.bridge_issue_component (issue_key, component_key)
        SELECT ic.issue_key, c.component_key
        FROM stg.jira_issue_component AS ic
        JOIN dm.dim_component         AS c ON c.component_name = ic.component_name;

        DECLARE @bridge_rows INT = @@ROWCOUNT;

        COMMIT TRANSACTION;

        ------------------------------------------------------------------
        -- Post-action: surface the upsert breakdown (the MERGE story).
        ------------------------------------------------------------------
        DECLARE @inserted INT = (SELECT COUNT(*) FROM @actions WHERE merge_action = N'INSERT');
        DECLARE @updated  INT = (SELECT COUNT(*) FROM @actions WHERE merge_action = N'UPDATE');

        PRINT CONCAT(N'dm.merge_fact_issue [', @snapshot_label, N']: ',
                     @inserted, N' inserted, ',
                     @updated,  N' updated, ',
                     @bridge_rows, N' bridge rows refreshed.');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
