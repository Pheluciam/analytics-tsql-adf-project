# INGESTION_PIPELINE.md — Jira REST → Azure SQL raw staging

> Phase 1 walkthrough. Companion to the clean definitions in `adf/` and
> `sql/ddl/01_create_raw_staging.sql`. Verification suite:
> `sql/verify/01_phase1_load_verification.sql`.

---

## What this layer does

One ADF Copy activity pulls the locked Jira JQL window
(`project = JRASERVER AND created >= 2015-01-01`, 19,339 issues at snapshot 1)
from the public Jira REST search endpoint, 500 issues per page, and lands **one
row per page** of raw, untouched JSON into `raw.jira_search_page`. No flattening,
no transformation — all shredding happens in T-SQL (Phase 2), which is this
project's lead theme.

```
jira.atlassian.com /rest/api/2/search          (anonymous, public)
        │  39 pages @ 500/page, 1s apart
        ▼
ADF Copy activity (pl_ingest_jira_snapshot)
        │  page JSON serialised to text
        ▼
Azure SQL  raw.jira_search_page                (NVARCHAR(MAX) + batch metadata)
```

## The architecture in one analogy

Think of a postal sorting office. The Copy activity is a courier sent to
collect a 19,339-page archive from a records office that only hands over
500 pages per visit. The courier makes 39 polite trips (one per second), each
time saying "continue from page N" (the `startAt` offset). Back at the
warehouse, each bundle is dropped into a numbered tray (one staging row per
page) with a delivery docket stapled on (run id, snapshot label, load time).
Nobody opens the bundles at the dock — reading and filing the individual pages
is the next department's job (the Phase 2 OPENJSON shred procs).

## How the pagination works (the part worth understanding)

The REST dataset's relative URL carries a placeholder:

```
...&startAt={offset}&maxResults=500...
```

Three pagination rules in the Copy source drive and bound the loop:

| Rule | Value | Role |
| --- | --- | --- |
| `AbsoluteUrl.{offset}` | `RANGE:0::500` | Fills the placeholder with 0, 500, 1000, ... (no fixed end) |
| `EndCondition:$.issues` | `Empty` | Stops when a page's `issues` array comes back empty |
| `MaxRequestNumber` | `50` | Runaway brake — hard cap on requests, whatever else happens |

Supporting choices:

- `supportRFC5988: false` — Jira doesn't paginate via `Link` headers; explicit
  rules only.
- `requestInterval: 00:00:01` — one second between page requests. Polite-paging
  mitigation against throttling of cloud IPs.
- `ORDER BY created ASC` inside the JQL — stable pagination. Issues created
  mid-pull append after the final page instead of shifting earlier pages.
- JQL is **percent-encoded by hand** in the relative URL; ADF does not encode
  it for you.

## How raw JSON lands as text (and the two gotchas)

The Copy mapping sends the response's top-level fields to the staging columns,
with `mapComplexValuesToString: true` serialising the whole `issues` array into
`page_json NVARCHAR(MAX)`:

| Source (response) | Sink column |
| --- | --- |
| `startAt` | `start_at` |
| `total` | `total_issues` |
| `issues` (serialised) | `page_json` |
| ADF additional column `pipeline_run_id` | `pipeline_run_id` |
| ADF additional column `snapshot_label` | `snapshot_label` |
| *(not mapped — database default)* | `load_utc` |

**Gotcha 1 — one addressing style per mapping.** Mixing JSONPath-style
(`$['startAt']`) and name-style (`pipeline_run_id`) source references in one
mapping fails with error 2200 *"Mixed properties are used to reference 'source'
columns"*. All references here are name-style — valid because every mapped
field is top-level. (LEARNINGS M2-2.)

**Gotcha 2 — the stop-probe row.** The empty page that fires the
`EndCondition` is still written to the sink: one extra row with an empty
`issues` array, on which this Jira instance echoes `startAt` as `0`. Snapshot 1
therefore has 40 rows: 39 data pages + 1 empty probe. Harmless by design —
`OPENJSON` over `[]` yields zero rows, so it can never reach the model. The
verification suite's duplicate-offset guard excludes empty pages for this
reason. (LEARNINGS M2-1.)

## Batch metadata and the snapshot pattern

- `snapshot_label` is a pipeline parameter (default `snapshot_1`). The Phase 3
  re-pull runs the same pipeline with `snapshot_2`, appending alongside the
  frozen first pull — that pair powers the MERGE upsert story.
- `pipeline_run_id` ties every row to one ADF run for lineage.
- `load_utc` is set by a database default (`SYSUTCDATETIME()`), not by ADF —
  one fewer mapping, and the timestamp is the database's own clock.
- Re-run procedure after a FAILED partial run: `DELETE FROM
  raw.jira_search_page WHERE pipeline_run_id = '<failed run id>';` then re-run
  with the same `snapshot_label`. The staging table is append-only otherwise.

## Why the UI wasn't enough

ADF Studio's pagination-rules editor exposes `AbsoluteUrl` but (as of this
build) not `EndCondition` or `MaxRequestNumber`, even though the engine
supports both. The pipeline was finished by editing its JSON directly in the
Studio code view ({} icon) — the JSON in `adf/pipeline/` is the source of
truth and is what's deployed. (LEARNINGS M2-3.)

## Snapshot 1 — verified result (2026-06-10)

| Check | Result |
| --- | --- |
| Pages landed | 40 (39 data + 1 empty stop-probe) |
| Coverage | `startAt` 0 → 19000, step 500, no gaps |
| Parity | issues landed 19,339 = API total 19,339 |
| Duplicates (non-empty) | 0 |
| Duration | 1m 43s end-to-end |

Security posture: anonymous public source; SQL credentials live only in ADF's
managed store and Phil's password manager; the repo's linked-service JSON is
sanitised (no password property); TLS mandatory with certificate validation on.
