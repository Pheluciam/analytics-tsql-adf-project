# PROJECT_CONTEXT.md — analytics-tsql-adf-project

> Living session log. Read alongside TEACHING_PREFERENCES.md at every session start.
> PROJECT_PLAN.md holds the locked scope; this file holds current state + closeouts.

---

## Current state (as of Phase 1 close, 2026-06-10)

- **Phase:** 1 COMPLETE — staging DDL + ADF ingestion pipeline + snapshot 1 landed and verified.
- **Next up:** Phase 2 — OPENJSON shred procs, dims + fact, MERGE upsert (the lead-theme core).
  Forward-verify pass at kickoff: OPENJSON typed shred patterns (WITH clause), MERGE
  best-practice on Azure SQL, TRY/CATCH + THROW conventions.

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
