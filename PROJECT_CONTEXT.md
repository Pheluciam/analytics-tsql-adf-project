# PROJECT_CONTEXT.md — analytics-tsql-adf-project

> Living session log. Read alongside TEACHING_PREFERENCES.md at every session start.
> PROJECT_PLAN.md holds the locked scope; this file holds current state + closeouts.

---

## Current state (as of Phase 0, 2026-06-10)

- **Phase:** 0 (environment + scaffold) — in progress.
- **Next up:** Phase 1 — staging DDL + ADF ingestion pipeline (pagination time-boxed 0.5 day).

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
