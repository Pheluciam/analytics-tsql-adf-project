/* ============================================================================
   01_phase1_load_verification.sql
   Phase 1 verification suite: snapshot 1 landed in raw.jira_search_page.
   Run each section separately after any pipeline run.
   Expected (snapshot 1, 2026-06-10): api_total = issues_landed = 19,339;
   39 data pages (startAt 0..19000 step 500) + possible 1 empty stop-probe page.
   ============================================================================ */

-- Section 1: staging schema exists with expected columns (7 rows expected)
SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name, ty.name AS data_type
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = N'raw'
ORDER BY c.column_id;

-- Section 2: page coverage + source-to-staging parity (the core check:
-- issues_landed MUST equal api_total)
SELECT
    COUNT(*)            AS pages,
    MIN(start_at)       AS first_page,
    MAX(start_at)       AS last_page,
    MAX(total_issues)   AS api_total,
    (SELECT SUM(j.cnt)
     FROM raw.jira_search_page AS p
     CROSS APPLY (SELECT COUNT(*) AS cnt FROM OPENJSON(p.page_json)) AS j) AS issues_landed
FROM raw.jira_search_page;

-- Section 3: per-page issue distribution (expect 500 per full page, the
-- remainder on the final page, 0 only on the pagination stop-probe row)
SELECT p.page_id, p.start_at, j.cnt AS issues_in_page
FROM raw.jira_search_page AS p
CROSS APPLY (SELECT COUNT(*) AS cnt FROM OPENJSON(p.page_json)) AS j
ORDER BY p.start_at, p.page_id;

-- Section 4: duplicate-offset guard (zero rows expected — duplicates would
-- mean a partial re-run appended on top of an existing snapshot).
-- Empty pages are excluded: the pagination stop-probe (the empty response that
-- fires EndCondition) is written as a row by ADF, with Jira echoing startAt 0.
-- Verified snapshot 1, 2026-06-10 — see LEARNINGS.md M2-1.
SELECT start_at, snapshot_label, COUNT(*) AS rows_per_offset
FROM raw.jira_search_page
WHERE page_json <> N'[]'
GROUP BY start_at, snapshot_label
HAVING COUNT(*) > 1;

-- Section 5: smoke sample — eyeball one row's metadata and JSON head
SELECT TOP 1 page_id, start_at, total_issues,
       LEFT(page_json, 300) AS json_head,
       pipeline_run_id, snapshot_label, load_utc
FROM raw.jira_search_page
ORDER BY page_id;
