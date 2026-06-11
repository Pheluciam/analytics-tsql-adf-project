# TSQL_MODEL.md — OPENJSON shred → star schema → MERGE upsert

> Phase 2 walkthrough. Companion to `sql/ddl/02_create_model_tables.sql` and
> the three procs in `sql/proc/`. Verification suite:
> `sql/verify/02_phase2_shred_model_verification.sql` (11 PASS/FAIL checks, one run).
> Upstream layer: INGESTION_PIPELINE.md.

---

## What this layer does

Everything between the raw landing zone and Power BI happens here, entirely in
T-SQL — this project's lead theme. Three stored procedures turn frozen page
JSON into a queryable star schema:

```
raw.jira_search_page          (40 rows of page JSON, Phase 1, frozen)
        │  EXEC stg.load_jira_issue @snapshot_label
        │  OPENJSON WITH-clause shred + dedupe + timestamp repair
        ▼
stg.jira_issue (+ stg.jira_issue_component)     (typed, truncate-and-reload)
        │  EXEC dm.merge_dimensions
        │  4 × MERGE: insert-new (status also updates category on drift)
        ▼
dm.dim_status / dim_priority / dim_issuetype / dim_component (+ static dim_date)
        │  EXEC dm.merge_fact_issue @snapshot_label
        │  MERGE upsert + OUTPUT $action counts + bridge refresh
        ▼
dm.fact_issue (one row per issue) + dm.bridge_issue_component
```

## The architecture in one analogy

Back to the postal sorting office from Phase 1: the bundles are now opened.
The shred proc is the mail-opening room — every page bundle is sliced into
individual letters (issues), each stamped into a fixed form (typed columns).
The dimension proc maintains the office's reference card-files: any new status,
priority, type or component gets a card with a number. The fact proc is the
filing department: each letter is filed in the master cabinet under its issue
key — new letters get a fresh folder (INSERT), letters about an existing case
update that folder (UPDATE), and the clerk keeps a tally of which was which
(OUTPUT $action). Nobody ever throws a folder away (no DELETE branch).

## Design decisions (the senior-DE calls)

- **Grain held at one row per issue.** Components are 0..n per issue, so a
  bridge table (`dm.bridge_issue_component`) carries the many-to-many instead
  of duplicating fact rows or concatenating names. Standard star answer.
- **Resolution is a degenerate attribute on the fact**, not a sixth dimension —
  a handful of labels with no attributes of their own.
- **Surrogate keys sized to cardinality** (TINYINT / SMALLINT) and FKs enforced
  on the fact: at 19K rows integrity is effectively free, and a broken load
  fails loudly instead of silently orphaning rows.
- **dim_date is populated inside the DDL** via `GENERATE_SERIES` (fixed range
  2015–2027): a calendar is static reference data, not pipeline state.
- **cycle_days is a PERSISTED computed column** — created→resolved day count
  stored once, read by every downstream view instead of recomputed per query.
- **stg is truncate-and-reload; dm is MERGE-maintained.** Staging is a
  disposable working surface; the star carries history (audit columns
  first_loaded_utc / last_updated_utc / last_snapshot_label power the Phase 3
  before/after upsert story).

## The OPENJSON shred (proc 1)

`OPENJSON(page_json)` iterates the page's issues array; the `WITH` clause
types each field by JSON path in one pass — nested paths reach through the
response structure (`$.fields.status.statusCategory.name`), and the
components array is kept as JSON (`AS JSON`) for a second-stage shred.

Three defensive layers, each tied to a forward-verified risk (LEARNINGS
M2-P2-1/2):

1. **Timestamp repair.** Jira emits `2015-01-08T03:23:34.000+0000` — the
   offset has no colon, which T-SQL won't parse. `STUFF` inserts the colon
   before the last two digits, `TRY_CONVERT(DATETIMEOFFSET, ...)` parses, and
   `SWITCHOFFSET(..., 0)` normalises to UTC before storing as DATETIME2(0).
2. **Dedupe guard.** The JQL orders by created ASC, so an issue updated
   mid-pull can drift across pages. `ROW_NUMBER()` per issue key keeps the
   most recently updated occurrence.
3. **Conversion check.** `TRY_CONVERT` fails silently to NULL — so after the
   load, any NULL created_utc raises error 50002 instead of leaking onward.

## The MERGE patterns (procs 2 and 3)

Guardrails per the forward-verify pass against the MERGE reference
(LEARNINGS M2-P2-3):

- `WITH (HOLDLOCK)` on every target — serializable range protection against
  insert/update races on the matched keys.
- **Key-only ON clauses** — all source filtering happens inside the USING
  derived table, so target access stays an index seek on the PK/UNIQUE key.
- **Change-only UPDATE branch** — `IS DISTINCT FROM` (NULL-safe, modern
  T-SQL) gates the MATCHED branch, so re-running the same snapshot updates
  zero rows and last_updated_utc stays an honest change marker.
- **No `WHEN NOT MATCHED BY SOURCE`** — issues never leave the locked JQL
  window, and a partial staging load must never delete facts.
- `OUTPUT $action` tallies INSERT vs UPDATE counts — snapshot 2 (Phase 3)
  re-runs the same proc and these counts become the upsert evidence.
- **Bridge refresh is delete-and-insert**, not MERGE: components are a full
  multi-valued set per issue, so set replacement is the correct (and simpler)
  semantics.
- Every proc: `SET XACT_ABORT, NOCOUNT ON`, explicit transaction, CATCH does
  `ROLLBACK` + parameterless `THROW` (preserves the original error), and
  pre-flight checks defend the run order (staging loaded? dims merged?).

## Run book

```sql
EXEC stg.load_jira_issue  @snapshot_label = N'snapshot_1';
EXEC dm.merge_dimensions;
EXEC dm.merge_fact_issue  @snapshot_label = N'snapshot_1';
```

Then run `sql/verify/02_phase2_shred_model_verification.sql` — one PASS/FAIL
grid (11 checks: parity, shred contract, dims, fact audit, bridge, dates)
plus two eyeball samples.

## Snapshot 1 — verified result (2026-06-11)

| Check | Result |
| --- | --- |
| Verify suite | 11 / 11 PASS |
| Staging parity (independent re-shred of raw) | 19,339 = 19,339 |
| Fact rows | 19,339 (insert-only on snapshot 1, audit clean) |
| Component links | 17,555 pairs, 150 components |
| Dimensions | 15 statuses, 5 priorities, 4 issue types |
| Date range | created from 2015-01-01, last resolution 2026-06-08 |
| Status-category mix | Done 64.0% / To Do 35.9% / In Progress 0.2% |

Portal Query editor quirks noted while running (LEARNINGS M2-7): PRINT output
is not displayed, and only the last result set of a multi-statement script is
rendered — highlight-and-run a selection to see an earlier result set.
