# PROJECT_CONTEXT.md — analytics-tsql-adf-project

> Living session log. Read alongside TEACHING_PREFERENCES.md at every session start.
> PROJECT_PLAN.md holds the locked scope; this file holds current state + closeouts.

---

## Current state (as of Phase 4 session 2 close, 2026-06-12)

- **Phase:** 4 COMPLETE — all three dashboard pages BUILT and polished
  (Backlog Pressure / Cycle Time & Ageing / Priority & Component Mix),
  25 documented measures (4 added this session), friendly titles + axis +
  tooltip labels across every visual, KPI accent bars on theme green.
  Screenshots in pbi/screenshots/ (01-03). .pbix saved at
  pbi/jira_ticket_ops_analytics.pbix.
- **Next up:** Phase 5 ship — README full pass (screenshots, data-audit note,
  AI-assistance disclosure, March-2025 bulk-cleanup finding), repo About +
  tags + profile entry + pin, final ENGINEERING_STANDARDS audit.

## Environment reference

- Azure portal identity: pheluciam@outlook.com — Azure subscription 1 (Active, Owner).
- Resource group: rg-analytics-tsql-adf (Australia East).
- SQL logical server: sql-analytics-tsql-adf-phm.database.windows.net
  - SQL auth admin: phil-sqladmin (password in password manager; later in local .env, gitignored).
- Database: sqldb-jira-issues (free offer: 100K vCore-seconds + 32GB/mo, auto-pause on limit).
- Data factory: adf-analytics-tsql-phm (V2, Australia East, no Git integration).
- Source: jira.atlassian.com REST search, anonymous. Locked JQL window:
  project = JRASERVER AND created >= 2015-01-01 (19,339 issues at audit, ~39 pages @500).

## Decisions log

- 2026-06-10 — JQL window locked to created >= 2015-01-01 (19,339 rows). 2020 window
  undershot target (6,972); longer history strengthens ageing + backlog-trend pages.
- 2026-06-10 — Free-offer DB region forced to Australia East: Azure requires all free
  DBs in one subscription to share the region of the first free DB (doc-verified;
  Project #2's sqldb-m5-source already occupies Australia East).
- 2026-06-10 — Working-style: design forks discussed in chat with trade-offs, not
  multiple-choice option widgets.
- 2026-06-10 (Phase 1) — Working-style SUPERSEDED: design forks are not put to Phil at
  all. Claude takes the senior-DE call (employer-lens), explains the trade-off briefly,
  proceeds. Locked in TEACHING_PREFERENCES as the North-star decision rule.
- 2026-06-10 (Phase 1) — Staging grain locked: one row per API page (page-level raw
  landing), not per issue. True bronze pattern, strongest OPENJSON story; the JObject
  serialisation risk tested empirically and did not fire (LEARNINGS M2-4).
- 2026-06-10 (Phase 1) — Pipeline JSON in the repo (adf/) is the source of truth; ADF
  Studio forms were insufficient (UI lags engine on pagination rules — LEARNINGS M2-3).
- 2026-06-10 (Phase 1) — Stop-probe row kept in staging (raw = verbatim); verification
  guard excludes empty pages instead (LEARNINGS M2-1).
- 2026-06-11 (Phase 4) — Classic time intelligence (marked date table + TOTALYTD etc.)
  over the new calendar-based preview: GA features only in portfolio work (M2-P4-2).
- 2026-06-11 (Phase 4) — vw_dim_date gained month_start_date: a 138-month categorical
  axis cramps and scrolls; a real DATE gives a continuous month-grain axis. Contract
  change made in T-SQL, not PQ (M2-P3-4 holds).
- 2026-06-11 (Phase 4) — '(none)' priority relabelled 'No Priority' in the pbi views,
  NOT in Power Query or dm. Roche's maxim: pbi schema IS the consumer-specific layer
  we own; label lives once, in source control, consistent across all three views.
- 2026-06-11 (Phase 4) — Inflow/outflow visual: diverging Net Monthly Flow bars
  (sign-coloured) instead of two-series columns (unreadable at 138 months) or a second
  line chart (rejected as lazy). Theme: built-in City Park; custom theme JSON rejected.
- 2026-06-12 (Phase 4 s2) — Cardinality rule for part-of-whole visuals: donut rejected
  at 10+ resolution categories (Phil's call) → sorted bar/column; component treemap
  capped with a visual-level Top N 10 filter for the same reason.
- 2026-06-12 (Phase 4 s2) — Role-playing trend measures get explicit USERELATIONSHIP
  variants (Median Cycle Days (Trend)) rather than re-wiring KPI measures; KPI tiles
  keep the active created-date context.
- 2026-06-12 (Phase 4 s2) — '(no component)' → 'No Component' relabelled in
  pbi.vw_priority_component_mix, T-SQL not PQ (Roche's maxim, third application);
  dependent DAX filter in Components with Open Work updated to match.
- 2026-06-12 (Phase 4 s2) — Measures audit: zero deletions. (Running) pair feeds
  Net Backlog; TI batch (YTD/MoM%/PM) kept as documented portfolio evidence.

## Session closeouts

### Phase 0 — 2026-06-10 (this session)

- Data audit re-run live: endpoint open, 51,783 JRASERVER issues, fields verified,
  500/page honoured. Window measured and locked (see decisions).
- Azure env: subscription confirmed Active; rg-analytics-tsql-adf + free-offer DB
  sqldb-jira-issues + server sql-analytics-tsql-adf-phm + adf-analytics-tsql-phm created.
  One mis-step banked: server panel initially saved as Australia Southeast (region
  mismatch error vs free-offer region rule) — redone in Australia East.
- PROJECT_PLAN.md + PROJECT_CONTEXT.md authored fresh.
- (pending this session) Git init + public repo + .gitignore + README skeleton;
  ENGINEERING_STANDARDS phase-boundary audit; bundled commit.

### Phase 1 — 2026-06-10 (this session)

- Forward-verify pass FIRST (per standards): ADF REST pagination rules verified against
  learn.microsoft.com; risks M2-P1-1..3 banked in LEARNINGS before any build.
- Staging layer: raw schema + raw.jira_search_page (page grain, NVARCHAR(MAX) JSON,
  batch metadata, ISJSON check) — sql/ddl/01_create_raw_staging.sql, ran clean.
- ADF (all published): ls_rest_jira (anonymous REST), ls_asql_sqldb_jira_issues
  (SQL auth, TLS mandatory, cert validation on), ds_rest_jira_search (encoded JQL +
  {offset} placeholder + ORDER BY created ASC), ds_asql_jira_search_page,
  pl_ingest_jira_snapshot (Copy: RANGE/EndCondition/MaxRequestNumber pagination,
  additional columns run-id + snapshot_label, mapComplexValuesToString). Definitions
  exported to adf/ (linked-service JSON sanitised, no password).
- Pagination well under the 0.5-day time-box; no fallback needed. One debug failure
  (mapping error 2200, fixed name-style — LEARNINGS M2-2), then SUCCESS in 1m43s.
- Snapshot 1 LANDED + VERIFIED + FROZEN: 40 rows (39 data pages + 1 empty stop-probe,
  LEARNINGS M2-1), coverage 0→19000 step 500, parity exact 19,339 = 19,339, zero
  non-empty duplicates. Suite: sql/verify/01_phase1_load_verification.sql (5 sections,
  all PASS, run by Phil end-to-end).
- INGESTION_PIPELINE.md walkthrough authored. LEARNINGS M2-1..5 banked.
- Working-style: North-star decision rule locked (no design-fork questions; senior-DE
  call, employer lens). Process-drift ledger M2-5.

### Phase 2 — 2026-06-11 (this session)

- Forward-verify pass FIRST: OPENJSON WITH-clause lax-NULL risk, Jira +0000 timestamp
  parse gap, MERGE guardrails (HOLDLOCK / key-only ON / indexed key), TRY/CATCH +
  THROW + XACT_ABORT convention — banked as M2-P2-1..4 before any build.
- Model DDL (sql/ddl/02): stg.jira_issue + stg.jira_issue_component (truncate-reload);
  dm.dim_status / dim_priority / dim_issuetype / dim_component (TINYINT/SMALLINT keys,
  UNIQUE natural keys); dm.dim_date 2015-2027 populated via GENERATE_SERIES (4,748 rows);
  dm.fact_issue (grain = issue key, FKs enforced, PERSISTED cycle_days, upsert audit
  columns); dm.bridge_issue_component (issue↔component many-to-many, grain preserved).
- Procs (sql/proc/01-03): stg.load_jira_issue (OPENJSON shred, STUFF timestamp repair,
  ROW_NUMBER dedupe, post-load conversion THROW); dm.merge_dimensions (4 MERGEs,
  HOLDLOCK, IS DISTINCT FROM change gate on status_category); dm.merge_fact_issue
  (MERGE upsert, change-only UPDATE branch, OUTPUT $action counts, bridge
  delete-and-insert, run-order pre-flights).
- Run end-to-end by Phil in portal Query editor: all procs sub-second to ~4s.
  Verify suite 02 (single PASS/FAIL grid, Phil-requested format from Project #3):
  11/11 PASS — parity 19,339 exact, 17,555 component pairs, 15/5/4/150 dim rows,
  insert-only audit clean, dates in range. Mix eyeball: Done 64% / To Do 35.9%.
- Bugs banked: M2-6 (predicate comparison syntax error), M2-7 (Query editor hides
  PRINT + shows only last result set).
- Working-style: ship-first debugging locked as standing default (M2-8);
  TEACHING_PREFERENCES updated in place.
- TSQL_MODEL.md walkthrough authored. LEARNINGS M2-P2-1..4 + M2-6..8 banked.

### Phase 3 — 2026-06-11 (this session)

- Forward-verify pass FIRST: CREATE VIEW engine doc + PBI Import guidance —
  ORDER BY illegal/meaningless in views, non-schemabound metadata freeze
  (no SELECT *), PERSISTED computed columns read clean through views,
  one PQ query = one view zero transforms. Banked M2-P3-1..4 before any build.
- pbi contract layer (sql/ddl/03): vw_backlog_flow (issue grain),
  vw_resolution_performance (issue grain: cycle_days, refresh-time age_days +
  ageing buckets with numeric sort column), vw_priority_component_mix
  (issue×component via bridge, LEFT JOIN keeps component-less, over-90d SLA
  flag), vw_dim_date passthrough. is_open defined once across all views
  (resolved_utc IS NULL). No SCHEMABINDING, explicit column lists.
- dm.merge_fact_issue edit: $action tallies now returned as a result set
  (portal suppresses PRINT — M2-7 applied forward, banked M2-10).
- Snapshot 2: pl_ingest_jira_snapshot debug-run with snapshot_label=snapshot_2
  (40 pages, 1m2s) → shred → merge. MERGE story: 2 INSERT / 5 UPDATE,
  bridge 17,555→17,558, fact 19,339→19,341. Unchanged rows kept snapshot_1
  audit labels — IS DISTINCT FROM gate verified honest.
- Verify suite 03 (single PASS/FAIL grid, dynamic counts): 11/11 PASS —
  raw two-snapshot integrity, staging truncate-reload contract, independent
  re-shred parity, audit-label integrity, view-grain contracts, cross-view
  open-definition consistency, cycle/age mutual exclusivity.
- One auto-pause resume failure on first portal query (banked M2-9).
- Bug caught by Phil at the eyeball: summary NULL on every fact row since
  Phase 2 — fields= list never requested it; lax-mode OPENJSON NULL (M2-P2-1
  fired for real). Fixed by dropping the column from stg/fact/procs (frozen
  snapshot_1 could never backfill it; no dashboard use; PII surface). M2-11.
- TSQL_MODEL.md Phase 3 section added. LEARNINGS M2-P3-1..4 + M2-9..11 banked.

### Phase 4 session 1 — 2026-06-11 (this session)

- Forward-verify pass FIRST: Azure SQL connector flow (2026-03 doc), mark-as-date-table
  mandatory for integer date keys, calendar-based TI is preview → classic chosen,
  relationship autodetect risk. Banked M2-P4-1..4 before opening PBI Desktop.
- Model built and verified: Import on the four pbi views only; autodetect off;
  5 hand-built relationships (created active ×3, resolved inactive ×2, all *:1
  single-direction into vw_dim_date.date_key); vw_dim_date marked as date table on
  date_value; keys hidden; month_name/day_name/age_bucket sort columns set;
  hidden _Measures table.
- 21 documented measures in 5 batches (inflow/outflow/backlog incl. USERELATIONSHIP
  outflow + cumulative VAR pattern, TOTALYTD/DATEADD/MoM%, cycle percentiles
  (MEDIAN / PERCENTILE.INC), mix DISTINCTCOUNTs, Resolution Rate %, Net Monthly Flow).
  Smoke test: resolved 12,371 + open 6,970 = 19,341 exact.
- Page 1 (Backlog Pressure — Demand vs Delivery) built: 5-tile new-Card KPI strip,
  Net Backlog cumulative line (12-year relative-date filter trims the future tail),
  diverging Net Monthly Flow bars (rule-based sign colouring), open-by-priority bar
  (headline finding: most open issues carry No Priority), calendar_year Between
  slicer. Page titles/subtitles locked for all three pages.
- View contract changes this session (deployed + mirrored to repo DDL):
  month_start_date added to vw_dim_date; '(none)' → 'No Priority' in three views.
- Bugs/quirks banked: M2-12 (DAX VAR name collided with LASTDATE function),
  M2-13 (new Card hides Display units until a specific card is selected).
- Working-style: container-first ordering + common-settings-bullets + narrow-tables
  rule locked into TEACHING_PREFERENCES after repeated format resets (M2-14).
- Deferred to session 2: pages 2-3, final polish (KPI-card colours flagged),
  screenshots, README.

### Phase 4 session 2 — 2026-06-12 (this session)

- Page 2 (Cycle Time & Ageing) built: 5-tile KPI strip (Median/Avg/P90 Cycle Days,
  Issues Resolved, % Resolved in 30 Days), median-cycle trend line on explicit
  USERELATIONSHIP variant, age-bucket bar (Over-365 dominates), resolution-type
  column (donut rejected at 10+ categories).
- Page 3 (Priority & Component Mix) built: 5-tile KPI strip (incl. new % Open
  No Priority + Components with Open Work), component treemap (Top 10 filter),
  SLA bar (counts; ~99% breach rate made the % variant a flat non-chart —
  % moved to tooltips), 100% stacked status-mix column.
- 4 new measures (25 total): % Resolved in 30 Days, Median Cycle Days (Trend),
  % Open No Priority, Components with Open Work. Measures audit: zero orphans.
- Polish pass all pages: KPI accent bars to theme green; Title-Case visual
  titles; Year slicer header; every axis/tooltip chip renamed friendly
  (Rename for this visual); month_start_date model format MMM yyyy; slicer
  connectivity verified on all pages.
- Analytics finding (Phil-driven): March 2025 median spike = bulk cleanup —
  724 resolutions (~8x normal month) at 2,580-day median; matches page 1
  outflow burst. README talking point; Issues Resolved kept in trend tooltip.
- View contract change (deployed + mirrored): '(no component)' → 'No Component'
  in vw_priority_component_mix.
- Bugs banked: M2-15 (DAX BLANK coerces to 0 in comparisons — % Resolved in
  30 Days admitted 6,970 open issues, 75.9% vs honest 19.5%).
- Process drift ledger: M2-14 recurrences banked (container-first/cascading
  bullets resets; full-list dump against the 1-page-per-chunk request).
- Screenshots 01-03 captured to pbi/screenshots/; .pbix saved.
