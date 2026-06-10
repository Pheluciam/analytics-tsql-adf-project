# Delivery Analytics Pipeline — Jira REST API → ADF → Azure SQL (T-SQL) → Power BI

End-to-end ticket-ops analytics mini-project: real Jira issue data ingested from a public
REST API by Azure Data Factory, staged as raw JSON in Azure SQL, shredded and modelled
entirely in T-SQL (OPENJSON, stored procedures, MERGE, views), and served to a 3-page
Power BI dashboard.

**Lead theme: T-SQL depth.** ADF is deliberately a thin courier (Copy + Stored Procedure
activities only); all transformation logic lives in version-controlled T-SQL.

> 🚧 Build in progress — Phase 0 (environment + scaffold) complete.

## Architecture

```
Jira REST API (jira.atlassian.com, anonymous, paginated)
        │  ADF Copy activity — raw JSON pages, no flattening
        ▼
Azure SQL Database (free offer) — staging: NVARCHAR(MAX) raw JSON
        │  T-SQL stored procedures — OPENJSON shred, MERGE upsert
        ▼
Star schema (dims + fact_issue) + presentation views
        │
        ▼
Power BI Desktop — semantic model + DAX, 3 report pages
```

## Data source + audit

Source is Atlassian's public Jira instance at jira.atlassian.com (Jira Server 10.3.13),
queried anonymously via the REST search endpoint. Audit re-verified live on 2026-06-10:
the JRASERVER project holds 51,783 issues, current to the day of audit; page size 500 is
honoured with classic startAt/maxResults pagination, and deep pagination was verified.
Fields verified present: key, issue type, status (with status category), priority, created,
updated, resolution date, resolution, and components. Sprint, story-point, and velocity
fields do not exist in this public tracker, and the dashboard scope is designed around
that. Extract window: issues created on or after 2015-01-01 (19,339 issues at audit,
~39 pages), pulled as a one-off frozen snapshot with a single later re-run to exercise
the MERGE upsert path.

**Data provenance / PII note:** this is real public issue-tracker data containing real
reporter and assignee names. Raw JSON is never committed to this repository; person
fields are aggregated or excluded from the model.

## Dashboard pages

1. **Backlog health + flow** — open vs resolved, inflow/outflow throughput, net backlog trend.
2. **Resolution performance** — created→resolved cycle days (percentiles), ageing of open issues, resolution-type mix.
3. **Priority / component mix** — distribution + SLA-style flags (e.g. open > 90 days by priority).

*(Screenshots land here at ship.)*

## Repository structure

```
sql/        T-SQL: DDL, shred + MERGE stored procedures, views, verification suites
adf/        Exported ADF pipeline/linked-service/dataset JSON definitions
powerbi/    .pbix semantic model + report
docs/       Walkthrough docs
```

## How this project was built

This project was built using AI-assisted pair programming (Claude by Anthropic).
All architecture decisions, technology selections, and final design choices are
my own; the AI accelerated implementation and acted as a senior-DE code reviewer.
The intent of the project is portfolio learning — every component was built with
explicit understanding of what it does and why. Walkthrough docs are in the
`docs/` folder; decision records are captured in `PROJECT_PLAN.md`.
