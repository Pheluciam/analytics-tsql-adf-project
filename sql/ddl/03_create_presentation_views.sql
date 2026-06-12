/* ============================================================================
   03_create_presentation_views.sql
   pbi schema — the Power BI Import contract layer (Phase 3).
   One view per locked dashboard concern (PROJECT_PLAN s5) + a date passthrough:
       pbi.vw_backlog_flow            page 1 — backlog health + flow
       pbi.vw_resolution_performance  page 2 — resolution performance
       pbi.vw_priority_component_mix  page 3 — priority / component mix
       pbi.vw_dim_date                shared — time-intelligence calendar
   Design rules (forward-verified, LEARNINGS M2-P3-1..4):
   - Explicit column lists, no SELECT * (non-schemabound views freeze metadata).
   - No SCHEMABINDING (keeps dm tables alterable; no indexed views needed).
   - No ORDER BY (illegal without TOP, meaningless anyway) — ordered buckets
     carry an explicit numeric sort column for PBI sort-by-column.
   - Dim labels denormalised in: one PQ query = one view, zero PQ transforms.
   - Open/closed defined ONCE, on resolution timestamps (is_open =
     resolved_utc IS NULL), consistent with cycle_days/age_days arithmetic.
   - age_days uses SYSUTCDATETIME() — recomputed at every PBI refresh,
     deliberately NOT frozen at load time.
   Walkthrough: TSQL_MODEL.md (repo root).
   ============================================================================ */

IF SCHEMA_ID(N'pbi') IS NULL
    EXEC (N'CREATE SCHEMA pbi');
GO

------------------------------------------------------------------------------
-- Page 1 — backlog health + flow. Issue grain. Inflow counts by created_date,
-- outflow by resolved_date, net backlog = running inflow - running outflow
-- (DAX over the two date keys; resolved relationship will be the inactive one).
------------------------------------------------------------------------------
CREATE OR ALTER VIEW pbi.vw_backlog_flow
AS
SELECT
    f.issue_key,
    t.issuetype_name,
    s.status_name,
    s.status_category,
    -- Phase 4: '(none)' relabelled at the presentation layer (BA-friendly axis
    -- label; dm keeps the raw value, PQ stays zero-transform per M2-P3-4)
    priority_name = CASE WHEN p.priority_name = N'(none)'
                         THEN N'No Priority' ELSE p.priority_name END,
    f.created_date_key,
    f.resolved_date_key,
    created_date  = CONVERT(DATE, f.created_utc),
    resolved_date = CONVERT(DATE, f.resolved_utc),
    is_open       = CASE WHEN f.resolved_utc IS NULL THEN 1 ELSE 0 END
FROM dm.fact_issue    AS f
JOIN dm.dim_status    AS s ON s.status_key    = f.status_key
JOIN dm.dim_priority  AS p ON p.priority_key  = f.priority_key
JOIN dm.dim_issuetype AS t ON t.issuetype_key = f.issuetype_key;
GO

------------------------------------------------------------------------------
-- Page 2 — resolution performance. Issue grain.
-- cycle_days (PERSISTED on the fact) for resolved issues; age_days computed
-- here at refresh time for open ones. Ageing buckets pre-labelled with a
-- numeric sort companion (M2-P3-1: never rely on row order).
------------------------------------------------------------------------------
CREATE OR ALTER VIEW pbi.vw_resolution_performance
AS
SELECT
    f.issue_key,
    t.issuetype_name,
    priority_name = CASE WHEN p.priority_name = N'(none)'
                         THEN N'No Priority' ELSE p.priority_name END,
    resolution_name = CASE WHEN f.resolved_utc IS NULL
                           THEN N'(unresolved)'
                           ELSE COALESCE(f.resolution_name, N'(none)') END,
    f.created_date_key,
    f.resolved_date_key,
    f.cycle_days,
    is_open  = CASE WHEN f.resolved_utc IS NULL THEN 1 ELSE 0 END,
    age_days = CASE WHEN f.resolved_utc IS NULL
                    THEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) END,
    age_bucket = CASE
                     WHEN f.resolved_utc IS NOT NULL THEN NULL
                     WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 30  THEN N'0-30 days'
                     WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 90  THEN N'31-90 days'
                     WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 365 THEN N'91-365 days'
                     ELSE N'Over 365 days'
                 END,
    age_bucket_sort = CASE
                          WHEN f.resolved_utc IS NOT NULL THEN NULL
                          WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 30  THEN 1
                          WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 90  THEN 2
                          WHEN DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) <= 365 THEN 3
                          ELSE 4
                      END
FROM dm.fact_issue    AS f
JOIN dm.dim_priority  AS p ON p.priority_key  = f.priority_key
JOIN dm.dim_issuetype AS t ON t.issuetype_key = f.issuetype_key;
GO

------------------------------------------------------------------------------
-- Page 3 — priority / component mix. Issue x component grain: the bridge
-- fans multi-component issues into one row per pair; LEFT JOIN keeps
-- component-less issues as 'No Component'. Issue-level measures on this
-- view must use DISTINCTCOUNT(issue_key) — documented for Phase 4 DAX.
-- SLA flag: open issues older than 90 days, evaluated at refresh time.
------------------------------------------------------------------------------
CREATE OR ALTER VIEW pbi.vw_priority_component_mix
AS
SELECT
    f.issue_key,
    priority_name = CASE WHEN p.priority_name = N'(none)'
                         THEN N'No Priority' ELSE p.priority_name END,
    t.issuetype_name,
    s.status_category,
    -- Phase 4: bracket label dropped for the BA-facing treemap ('No Component'
    -- matches the 'No Priority' relabel precedent; dm keeps NULL semantics)
    component_name = COALESCE(c.component_name, N'No Component'),
    f.created_date_key,
    is_open = CASE WHEN f.resolved_utc IS NULL THEN 1 ELSE 0 END,
    is_open_over_90d = CASE WHEN f.resolved_utc IS NULL
                             AND DATEDIFF(DAY, f.created_utc, SYSUTCDATETIME()) > 90
                            THEN 1 ELSE 0 END
FROM dm.fact_issue              AS f
JOIN dm.dim_status              AS s ON s.status_key    = f.status_key
JOIN dm.dim_priority            AS p ON p.priority_key  = f.priority_key
JOIN dm.dim_issuetype           AS t ON t.issuetype_key = f.issuetype_key
LEFT JOIN dm.bridge_issue_component AS b ON b.issue_key = f.issue_key
LEFT JOIN dm.dim_component      AS c ON c.component_key = b.component_key;
GO

------------------------------------------------------------------------------
-- Shared calendar — passthrough so the whole PBI model imports from one
-- schema surface. Relationships: created_date_key (active) and
-- resolved_date_key (inactive, via USERELATIONSHIP) -> date_key.
------------------------------------------------------------------------------
CREATE OR ALTER VIEW pbi.vw_dim_date
AS
SELECT
    d.date_key,
    d.date_value,
    d.calendar_year,
    d.calendar_quarter,
    d.calendar_month,
    d.month_name,
    d.day_of_month,
    d.day_of_week_iso,
    d.day_name,
    d.is_weekend,
    d.year_month_label,
    -- Phase 4: month-grain continuous axis for PBI trend charts (a 138-month
    -- categorical axis cramps and scrolls; a real DATE keeps the axis clean)
    month_start_date = DATEFROMPARTS(d.calendar_year, d.calendar_month, 1)
FROM dm.dim_date AS d;
GO
