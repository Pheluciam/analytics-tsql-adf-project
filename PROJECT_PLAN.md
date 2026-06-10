# PROJECT_PLAN.md — analytics-tsql-adf-project (Mini #2 of 3)

> Authored fresh at Phase 0 (2026-06-10) from MINI2_KICKOFF.md.
> Lead theme: **T-SQL depth** (OPENJSON shredding, stored procedures, MERGE, views).
> Budget: **3-5 days max at ~6 hrs/day. Cut scope rather than extend. ONE lead theme.**

---

## 1. Objective

Build a portfolio mini-project demonstrating T-SQL depth on a real REST API source:
Jira issue data ingested by Azure Data Factory into Azure SQL as raw JSON, shredded
and modelled entirely in T-SQL, served to a 3-page Power BI Desktop dashboard.

Domain story: **delivery / ticket-ops analytics** (new ops sub-domain; distinct from
transit, retail demand, corporate finance, warehouse distribution).

## 2. Pipeline (locked)

Jira REST API (jira.atlassian.com, anonymous)
→ ADF (**Copy + Stored Procedure activities ONLY** — no Mapping Data Flows, no flattening)
→ Azure SQL free-offer DB (raw JSON staged as NVARCHAR(MAX))
→ T-SQL: OPENJSON shred procs, MERGE upsert procs, TRY/CATCH, presentation views
→ Power BI Desktop star schema + documented DAX (incl. time intelligence)
→ deliverable: .pbix in repo + screenshots in README.

## 3. Data source (pre-flight PASSED 2026-06-10, re-verified same day at Phase 0)

- Atlassian public Jira: jira.atlassian.com (Jira Server 10.3.13), REST search endpoint,
  anonymous, classic startAt/maxResults/total pagination, page size 500 honoured.
- JRASERVER project: 51,783 issues total, current to day of audit.
- **Extract window LOCKED: project = JRASERVER AND created >= 2015-01-01 → 19,339 issues
  (~39 pages at 500/page).** Snapshot pattern: pull once, freeze raw JSON; one later
  re-run feeds the MERGE upsert story.
- Fields verified: key, issuetype, status (+statusCategory), priority, created, updated,
  resolutiondate, resolution, components, assignee (often null).
- NOT in this data: sprints, story points, epics, velocity, burndown. Nothing is designed
  to need them.
- Changelog (?expand=changelog, one call per issue): **STRETCH ONLY.**

## 4. Azure environment (verified + created at Phase 0, 2026-06-10)

- Identity: pheluciam@outlook.com. Subscription: Azure subscription 1 (Active, Owner).
- Resource group: rg-analytics-tsql-adf (Australia East).
- Logical server: sql-analytics-tsql-adf-phm.database.windows.net (Australia East,
  SQL auth, admin login phil-sqladmin — password in Phil's password manager / .env only).
- Database: sqldb-jira-issues — Azure SQL free offer (100K vCore-seconds + 32GB/month,
  auto-pause when free limit reached). Note: all free DBs in a subscription must share
  one region (Australia East here) — doc-verified at Phase 0.
- Data factory: adf-analytics-tsql-phm (V2, Australia East, public endpoint, no Git config).

## 5. Dashboard pages (LOCKED — no day-3 pivots)

1. **Backlog health + flow** — open vs resolved, inflow/outflow throughput, net backlog trend.
2. **Resolution performance** — created→resolved cycle days (percentiles), ageing of open
   issues, resolution-type mix.
3. **Priority / component mix** — distribution + SLA-style flags (e.g. open > 90 days by
   priority).

## 6. Phase breakdown (3-5 days)

- **Phase 0 (day 0, this session)** — Azure env verified + created; data audit re-run;
  plan + context docs; git init + public repo + .gitignore + README skeleton;
  ENGINEERING_STANDARDS audit at boundary. ✅ in progress
- **Phase 1 (day 1)** — Staging layer + ingestion.
  - T-SQL: raw schema, staging table(s) for raw JSON pages (NVARCHAR(MAX)), load-batch
    metadata columns.
  - ADF: linked services (REST + Azure SQL), datasets, Copy pipeline with pagination
    over the locked JQL window. **Pagination loop time-boxed to 0.5 day** — fallbacks:
    Lookup total → ForEach computed page list; last resort local extractor (PowerShell/
    Python) lands JSON files, ADF still does file → SQL.
  - Snapshot 1 landed and frozen.
- **Phase 2 (day 2)** — T-SQL shred + model (the lead-theme core).
  - OPENJSON shred procs (staging JSON → typed issue rows), TRY/CATCH + DECLARE patterns.
  - Dimension + fact tables (flat star: dim_status, dim_priority, dim_issuetype,
    dim_component, dim_date; fact_issue grain = one row per issue).
  - MERGE upsert proc(s) keyed on issue key.
- **Phase 3 (day 3)** — Views + MERGE story + second pull.
  - Presentation views for PBI (one per dashboard concern).
  - Re-run pipeline (snapshot 2): changed issues exercise MERGE updates — the upsert
    narrative, verified with before/after counts.
- **Phase 4 (day 3-4)** — Power BI.
  - Star schema semantic model on the views; _Measures table; documented DAX incl.
    time intelligence; 3 locked pages.
- **Phase 5 (day 4-5)** — Ship.
  - README full pass (screenshots, data-audit note, AI-assistance disclosure), repo About
    + tags + profile entry + pin, final ENGINEERING_STANDARDS audit, bundled commit.

## 7. Risks + mitigations (banked 2026-06-10)

1. **ADF REST pagination loop** — fiddliest bit; time-box 0.5 day; fallbacks per Phase 1.
2. **Atlassian throttling of Azure IPs** — snapshot pattern, polite sequential paging;
   full block → local-extractor fallback.
3. **Azure subscription state** — CLEARED at Phase 0: sub Active, free-offer DB + ADF created.
4. **PII hygiene** — raw JSON NEVER committed (.gitignore from day 1); person fields
   aggregated or excluded in the model; README carries data-provenance note.

## 8. Scope discipline

- ONE endpoint (search), issues only, flat star schema.
- Feature-creep watchlist (all OUT unless explicitly re-scoped): changelog mining,
  custom-field sprawl, burndown reconstruction, multi-project pulls.
- Changelog/cycle-time events = stretch, only if days 1-3 land early.
- Past 5 days → cut scope, do not extend.

## 9. Conventions

- ALL SQL KEYWORDS UPPERCASE. snake_case identifiers. NVARCHAR for strings.
- ENGINEERING_STANDARDS ten-point audit per script + structural audit at phase boundaries;
  forward-verify pass at each phase kickoff.
- One bundled commit per session. README per Project #3 portfolio template incl.
  AI-assistance disclosure. Shipping = About + tags + profile entry + pin.
