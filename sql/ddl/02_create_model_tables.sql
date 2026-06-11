/* ============================================================================
   02_create_model_tables.sql
   Typed staging + flat star schema for Jira issue analytics (Phase 2).
   Layers: stg (typed shred target, truncate-and-reload per snapshot)
           dm  (dimensions + fact, persistent, maintained by MERGE procs).
   Re-runnable during Phase 2 iteration (drop-and-recreate, child tables first).
   Model data is fully re-derivable from raw.jira_search_page at any time.
   Walkthrough: TSQL_MODEL.md (repo root).
   ============================================================================ */

------------------------------------------------------------------------------
-- Schemas. CREATE SCHEMA must be the only statement in its batch, hence EXEC.
------------------------------------------------------------------------------
IF SCHEMA_ID(N'stg') IS NULL
    EXEC (N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'dm') IS NULL
    EXEC (N'CREATE SCHEMA dm');
GO

-- Drop order: FK children before parents.
DROP TABLE IF EXISTS dm.bridge_issue_component;
DROP TABLE IF EXISTS dm.fact_issue;
DROP TABLE IF EXISTS dm.dim_status;
DROP TABLE IF EXISTS dm.dim_priority;
DROP TABLE IF EXISTS dm.dim_issuetype;
DROP TABLE IF EXISTS dm.dim_component;
DROP TABLE IF EXISTS dm.dim_date;
DROP TABLE IF EXISTS stg.jira_issue_component;
DROP TABLE IF EXISTS stg.jira_issue;
GO

------------------------------------------------------------------------------
-- stg.jira_issue — one row per issue, latest snapshot only (truncate-reload).
-- Lenient NULLability by design: staging accepts what the shred produces;
-- the verify suite and the fact MERGE pre-flight enforce the contract.
------------------------------------------------------------------------------
CREATE TABLE stg.jira_issue
(
    issue_key       NVARCHAR(20)  NOT NULL,
    issue_id        INT           NOT NULL,

    -- Dim attributes COALESCEd to N'(none)' at load time, so dim lookups
    -- never have to handle NULL business keys.
    status_name     NVARCHAR(60)  NULL,
    status_category NVARCHAR(30)  NULL,
    priority_name   NVARCHAR(30)  NULL,
    issuetype_name  NVARCHAR(60)  NULL,
    resolution_name NVARCHAR(60)  NULL,

    -- Converted from Jira's +0000-suffixed timestamps; stored as UTC.
    created_utc     DATETIME2(0)  NULL,
    updated_utc     DATETIME2(0)  NULL,
    resolved_utc    DATETIME2(0)  NULL,

    -- The issue's components[] array kept as JSON for the second-stage shred.
    components_json NVARCHAR(MAX) NULL,

    -- Lineage back to the raw landing row.
    page_id         INT           NOT NULL,
    snapshot_label  NVARCHAR(30)  NOT NULL,

    -- PK doubles as the dedupe guard: the load proc keeps one row per key.
    CONSTRAINT pk_stg_jira_issue PRIMARY KEY CLUSTERED (issue_key)
);
GO

CREATE TABLE stg.jira_issue_component
(
    issue_key      NVARCHAR(20)  NOT NULL,
    component_name NVARCHAR(100) NOT NULL,

    CONSTRAINT pk_stg_jira_issue_component
        PRIMARY KEY CLUSTERED (issue_key, component_name)
);
GO

------------------------------------------------------------------------------
-- Dimensions. Surrogate keys sized to actual cardinality (free-tier-aware):
-- TINYINT covers status/priority/issuetype, SMALLINT covers components.
-- Natural keys carry UNIQUE constraints — the MERGE procs match on them.
------------------------------------------------------------------------------
CREATE TABLE dm.dim_status
(
    status_key      TINYINT IDENTITY (1, 1) NOT NULL,
    status_name     NVARCHAR(60)            NOT NULL,
    -- Jira's three-way rollup (To Do / In Progress / Done) — drives the
    -- open-vs-resolved cut on dashboard page 1.
    status_category NVARCHAR(30)            NOT NULL,

    CONSTRAINT pk_dim_status PRIMARY KEY CLUSTERED (status_key),
    CONSTRAINT uq_dim_status_name UNIQUE (status_name)
);
GO

CREATE TABLE dm.dim_priority
(
    priority_key  TINYINT IDENTITY (1, 1) NOT NULL,
    priority_name NVARCHAR(30)            NOT NULL,

    CONSTRAINT pk_dim_priority PRIMARY KEY CLUSTERED (priority_key),
    CONSTRAINT uq_dim_priority_name UNIQUE (priority_name)
);
GO

CREATE TABLE dm.dim_issuetype
(
    issuetype_key  TINYINT IDENTITY (1, 1) NOT NULL,
    issuetype_name NVARCHAR(60)            NOT NULL,

    CONSTRAINT pk_dim_issuetype PRIMARY KEY CLUSTERED (issuetype_key),
    CONSTRAINT uq_dim_issuetype_name UNIQUE (issuetype_name)
);
GO

CREATE TABLE dm.dim_component
(
    component_key  SMALLINT IDENTITY (1, 1) NOT NULL,
    component_name NVARCHAR(100)            NOT NULL,

    CONSTRAINT pk_dim_component PRIMARY KEY CLUSTERED (component_key),
    CONSTRAINT uq_dim_component_name UNIQUE (component_name)
);
GO

------------------------------------------------------------------------------
-- dm.dim_date — fixed range 2015-01-01..2027-12-31 (extract window + headroom
-- for resolution dates and snapshot 2). Populated below in this script:
-- a calendar is static reference data, so DDL owns it, not a proc.
------------------------------------------------------------------------------
CREATE TABLE dm.dim_date
(
    date_key         INT          NOT NULL,  -- yyyymmdd
    date_value       DATE         NOT NULL,
    calendar_year    SMALLINT     NOT NULL,
    calendar_quarter TINYINT      NOT NULL,
    calendar_month   TINYINT      NOT NULL,
    month_name       NVARCHAR(10) NOT NULL,
    day_of_month     TINYINT      NOT NULL,
    -- ISO numbering (Mon=1..Sun=7), computed independently of DATEFIRST so
    -- the value can never drift with session settings.
    day_of_week_iso  TINYINT      NOT NULL,
    day_name         NVARCHAR(10) NOT NULL,
    is_weekend       BIT          NOT NULL,
    year_month_label NCHAR(7)     NOT NULL,  -- '2015-01' — PBI trend axes

    CONSTRAINT pk_dim_date PRIMARY KEY CLUSTERED (date_key),
    CONSTRAINT uq_dim_date_value UNIQUE (date_value)
);
GO

INSERT INTO dm.dim_date
        (date_key, date_value, calendar_year, calendar_quarter, calendar_month,
         month_name, day_of_month, day_of_week_iso, day_name, is_weekend,
         year_month_label)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), d.date_value, 112)),
    d.date_value,
    DATEPART(YEAR, d.date_value),
    DATEPART(QUARTER, d.date_value),
    DATEPART(MONTH, d.date_value),
    DATENAME(MONTH, d.date_value),
    DATEPART(DAY, d.date_value),
    d.dow_iso,
    DATENAME(WEEKDAY, d.date_value),
    CASE WHEN d.dow_iso >= 6 THEN 1 ELSE 0 END,
    CONVERT(NCHAR(7), d.date_value, 23)
FROM (
    SELECT
        date_value = DATEADD(DAY, s.value, '2015-01-01'),
        -- DATEFIRST-independent ISO weekday: 2015-01-05 is a known Monday.
        dow_iso    = (DATEDIFF(DAY, '2015-01-05',
                               DATEADD(DAY, s.value, '2015-01-01')) % 7 + 7) % 7 + 1
    FROM GENERATE_SERIES(0, DATEDIFF(DAY, '2015-01-01', '2027-12-31')) AS s
) AS d;
GO

------------------------------------------------------------------------------
-- dm.fact_issue — grain: one row per Jira issue, keyed on the issue key.
-- Maintained by dm.merge_fact_issue (MERGE upsert). FKs enforced: 19K rows
-- make integrity effectively free, and orphans fail loudly at load time.
------------------------------------------------------------------------------
CREATE TABLE dm.fact_issue
(
    issue_key           NVARCHAR(20)  NOT NULL,
    issue_id            INT           NOT NULL,

    status_key          TINYINT       NOT NULL,
    priority_key        TINYINT       NOT NULL,
    issuetype_key       TINYINT       NOT NULL,
    -- Low-cardinality label, not one of the five locked dims — lives on the
    -- fact as a degenerate attribute; feeds the resolution-mix visual.
    resolution_name     NVARCHAR(60)  NULL,

    created_date_key    INT           NOT NULL,
    resolved_date_key   INT           NULL,
    created_utc         DATETIME2(0)  NOT NULL,
    updated_utc         DATETIME2(0)  NULL,
    resolved_utc        DATETIME2(0)  NULL,

    -- Created→resolved cycle time; NULL while open. PERSISTED so views and
    -- PBI read a stored value instead of recomputing per query.
    cycle_days AS DATEDIFF(DAY, created_utc, resolved_utc) PERSISTED,

    -- Upsert audit trail — before/after evidence for the Phase 3 MERGE story.
    first_loaded_utc    DATETIME2(0)  NOT NULL
        CONSTRAINT df_fact_issue_first_loaded DEFAULT SYSUTCDATETIME(),
    last_updated_utc    DATETIME2(0)  NOT NULL
        CONSTRAINT df_fact_issue_last_updated DEFAULT SYSUTCDATETIME(),
    last_snapshot_label NVARCHAR(30)  NOT NULL,

    CONSTRAINT pk_fact_issue PRIMARY KEY CLUSTERED (issue_key),
    CONSTRAINT uq_fact_issue_id UNIQUE (issue_id),

    CONSTRAINT fk_fact_issue_status
        FOREIGN KEY (status_key)        REFERENCES dm.dim_status (status_key),
    CONSTRAINT fk_fact_issue_priority
        FOREIGN KEY (priority_key)      REFERENCES dm.dim_priority (priority_key),
    CONSTRAINT fk_fact_issue_issuetype
        FOREIGN KEY (issuetype_key)     REFERENCES dm.dim_issuetype (issuetype_key),
    CONSTRAINT fk_fact_issue_created_date
        FOREIGN KEY (created_date_key)  REFERENCES dm.dim_date (date_key),
    CONSTRAINT fk_fact_issue_resolved_date
        FOREIGN KEY (resolved_date_key) REFERENCES dm.dim_date (date_key)
);
GO

------------------------------------------------------------------------------
-- dm.bridge_issue_component — resolves the issue↔component many-to-many
-- while fact_issue keeps its one-row-per-issue grain. Refreshed alongside
-- the fact MERGE (delete-and-insert per loaded issue set).
------------------------------------------------------------------------------
CREATE TABLE dm.bridge_issue_component
(
    issue_key     NVARCHAR(20) NOT NULL,
    component_key SMALLINT     NOT NULL,

    CONSTRAINT pk_bridge_issue_component
        PRIMARY KEY CLUSTERED (issue_key, component_key),
    CONSTRAINT fk_bridge_issue
        FOREIGN KEY (issue_key)     REFERENCES dm.fact_issue (issue_key),
    CONSTRAINT fk_bridge_component
        FOREIGN KEY (component_key) REFERENCES dm.dim_component (component_key)
);
GO
