/* ============================================================================
   01_create_raw_staging.sql
   Raw landing zone for Jira REST search pages (Phase 1).
   Grain: one row per API page (~39 rows per snapshot at 500 issues/page).
   Re-runnable during Phase 1 schema iteration ONLY (drop-and-recreate).
   Do NOT re-run after snapshot 1 is frozen — snapshot 2 APPENDS to this table.
   Walkthrough: INGESTION_PIPELINE.md (repo root).
   ============================================================================ */

-- Landing schema. CREATE SCHEMA must run in its own batch, hence EXEC.
IF SCHEMA_ID(N'raw') IS NULL
    EXEC (N'CREATE SCHEMA raw');
GO

DROP TABLE IF EXISTS raw.jira_search_page;
GO

CREATE TABLE raw.jira_search_page
(
    page_id         INT IDENTITY (1, 1) NOT NULL,

    -- Echo of the request offset (response $.startAt). With total_issues,
    -- proves full page coverage at verification time.
    start_at        INT                 NOT NULL,

    -- API-reported total at pull time (response $.total). Same value on
    -- every page of one snapshot; drift between snapshots feeds the MERGE story.
    total_issues    INT                 NOT NULL,

    -- The page's raw issues[] array exactly as returned. No flattening here —
    -- OPENJSON shredding happens in Phase 2 procs. No compression: large
    -- NVARCHAR(MAX) values store off-row where PAGE compression has no effect.
    page_json       NVARCHAR(MAX)       NOT NULL,

    -- ADF Copy "additional columns": pipeline().RunId + snapshot label parameter.
    pipeline_run_id NVARCHAR(40)        NOT NULL,
    snapshot_label  NVARCHAR(30)        NOT NULL,

    -- Set by the database at insert, not by ADF — one fewer pipeline mapping.
    load_utc        DATETIME2(0)        NOT NULL
        CONSTRAINT df_jira_search_page_load_utc DEFAULT SYSUTCDATETIME(),

    CONSTRAINT pk_jira_search_page PRIMARY KEY CLUSTERED (page_id),

    -- Reject malformed payloads at the door (pre-flight check baked into DDL).
    CONSTRAINT ck_jira_search_page_isjson CHECK (ISJSON(page_json) = 1)
);
GO
