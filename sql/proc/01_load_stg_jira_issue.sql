/* ============================================================================
   01_load_stg_jira_issue.sql
   stg.load_jira_issue — OPENJSON shred: raw page JSON → typed issue rows.
   Truncate-and-reload per snapshot; safe to re-run any time (idempotent).
   Forward-verified risks: M2-P2-1 (lax-mode NULLs), M2-P2-2 (+0000 offsets).
   Walkthrough: TSQL_MODEL.md (repo root).
   ============================================================================ */

CREATE OR ALTER PROCEDURE stg.load_jira_issue
    @snapshot_label NVARCHAR(30)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- Pre-flight: the requested snapshot must exist in raw.
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1
                       FROM raw.jira_search_page
                       WHERE snapshot_label = @snapshot_label)
        BEGIN
            ;THROW 50001, N'stg.load_jira_issue: no raw pages found for the requested snapshot_label.', 1;
        END;

        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.jira_issue_component;
        TRUNCATE TABLE stg.jira_issue;

        ------------------------------------------------------------------
        -- Shred pass 1: pages → typed issue rows.
        -- Timestamps land as NVARCHAR(30) first because Jira's +0000 zone
        -- suffix has no colon and cannot CAST to DATETIMEOFFSET directly
        -- (M2-P2-2): STUFF inserts the colon, then convert and store UTC.
        -- Empty stop-probe pages contribute zero rows by OPENJSON semantics.
        ------------------------------------------------------------------
        WITH shredded AS
        (
            SELECT
                p.page_id,
                p.snapshot_label,
                j.issue_key,
                j.issue_id,
                j.summary,
                status_name     = COALESCE(j.status_name, N'(none)'),
                status_category = COALESCE(j.status_category, N'(none)'),
                priority_name   = COALESCE(j.priority_name, N'(none)'),
                issuetype_name  = COALESCE(j.issuetype_name, N'(none)'),
                j.resolution_name,
                created_utc  = CONVERT(DATETIME2(0), SWITCHOFFSET(
                                   TRY_CONVERT(DATETIMEOFFSET,
                                       STUFF(j.created_raw,  LEN(j.created_raw)  - 1, 0, N':')), 0)),
                updated_utc  = CONVERT(DATETIME2(0), SWITCHOFFSET(
                                   TRY_CONVERT(DATETIMEOFFSET,
                                       STUFF(j.updated_raw,  LEN(j.updated_raw)  - 1, 0, N':')), 0)),
                resolved_utc = CONVERT(DATETIME2(0), SWITCHOFFSET(
                                   TRY_CONVERT(DATETIMEOFFSET,
                                       STUFF(j.resolved_raw, LEN(j.resolved_raw) - 1, 0, N':')), 0)),
                j.components_json
            FROM raw.jira_search_page AS p
            CROSS APPLY OPENJSON(p.page_json)
                WITH (
                    issue_key       NVARCHAR(20)  N'$.key',
                    issue_id        INT           N'$.id',
                    summary         NVARCHAR(400) N'$.fields.summary',
                    status_name     NVARCHAR(60)  N'$.fields.status.name',
                    status_category NVARCHAR(30)  N'$.fields.status.statusCategory.name',
                    priority_name   NVARCHAR(30)  N'$.fields.priority.name',
                    issuetype_name  NVARCHAR(60)  N'$.fields.issuetype.name',
                    resolution_name NVARCHAR(60)  N'$.fields.resolution.name',
                    created_raw     NVARCHAR(30)  N'$.fields.created',
                    updated_raw     NVARCHAR(30)  N'$.fields.updated',
                    resolved_raw    NVARCHAR(30)  N'$.fields.resolutiondate',
                    components_json NVARCHAR(MAX) N'$.fields.components' AS JSON
                ) AS j
            WHERE p.snapshot_label = @snapshot_label
        ),
        ------------------------------------------------------------------
        -- Dedupe guard: an issue updated mid-pull can appear on two pages
        -- (JQL orders by created ASC, so it shifts forward). Keep the most
        -- recently updated occurrence per key.
        ------------------------------------------------------------------
        deduped AS
        (
            SELECT *,
                   rn = ROW_NUMBER() OVER (PARTITION BY issue_key
                                           ORDER BY updated_utc DESC, page_id DESC)
            FROM shredded
        )
        INSERT INTO stg.jira_issue
                (issue_key, issue_id, summary,
                 status_name, status_category, priority_name, issuetype_name,
                 resolution_name, created_utc, updated_utc, resolved_utc,
                 components_json, page_id, snapshot_label)
        SELECT issue_key, issue_id, summary,
               status_name, status_category, priority_name, issuetype_name,
               resolution_name, created_utc, updated_utc, resolved_utc,
               components_json, page_id, snapshot_label
        FROM deduped
        WHERE rn = 1;

        DECLARE @issue_rows INT = @@ROWCOUNT;

        ------------------------------------------------------------------
        -- Shred pass 2: each issue's components[] array → name rows.
        ------------------------------------------------------------------
        INSERT INTO stg.jira_issue_component (issue_key, component_name)
        SELECT DISTINCT
               i.issue_key,
               c.component_name
        FROM stg.jira_issue AS i
        CROSS APPLY OPENJSON(i.components_json)
            WITH (component_name NVARCHAR(100) N'$.name') AS c
        WHERE c.component_name IS NOT NULL;

        DECLARE @component_rows INT = @@ROWCOUNT;

        COMMIT TRANSACTION;

        ------------------------------------------------------------------
        -- Post-action verification: every conversion must have succeeded.
        -- TRY_CONVERT turns a malformed timestamp into NULL silently —
        -- surface that here instead of letting it hide (M2-P2-1/2).
        ------------------------------------------------------------------
        DECLARE @bad_dates INT =
            (SELECT COUNT(*) FROM stg.jira_issue WHERE created_utc IS NULL);

        IF @bad_dates > 0
        BEGIN
            ;THROW 50002, N'stg.load_jira_issue: created_utc is NULL on one or more rows — timestamp conversion failed; inspect stg.jira_issue.', 1;
        END;

        PRINT CONCAT(N'stg.load_jira_issue [', @snapshot_label, N']: ',
                     @issue_rows, N' issues, ',
                     @component_rows, N' issue-component rows loaded.');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
