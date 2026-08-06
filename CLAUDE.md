# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The centralized data platform for a moving-services business group: a single, trustworthy data source that serves both reporting and internal applications built by other teams.

The repository holds the ingestion pipeline, architecture docs, SmartMoving API reference material, seed dimension mappings, and sample report exports.

**Priorities, in order:**

1. One reliable data source other teams can consume without ever calling a vendor API themselves.
2. Data as fresh as each source allows, against published freshness targets.
3. Retire the team's Google Sheets pipelines.

If a proposed change does not serve one of those three, it is out of scope for the current phase.

## Current phase

**Phase 1 - SmartMoving into Postgres.** Single source, single destination, serving layer published, first Google Sheet retired.

Do not add sources, tools, or layers beyond what Phase 1 requires. Phase gates are defined under "Roadmap".

## Target architecture

**In use now:**

- **dlt** (Python) - extraction from source APIs
- **PostgreSQL** - the central store; raw, core, marts, and serving layers in one database
- **dbt Core** (`dbt-postgres` adapter) - transformation
- **n8n** - webhook ingestion, scheduling, email/report event capture
- **Metabase** - BI during the validation period

**Deferred. Do not build until the trigger fires:**

| Component          | Trigger to adopt                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Analytical warehouse (columnar) | Analytical queries degrade application performance even on a read replica, or history outgrows what an operational database should carry |
| Dagster            | n8n scheduling becomes the bottleneck: more than ~15 interdependent jobs, or backfill/retry logic becomes unmanageable                   |
| Cube Core          | Three or more independent consumers need guaranteed-identical metric definitions                                                         |
| Custom BI websites | Serving contracts are stable and Metabase is demonstrably insufficient                                                                   |

Each deferred component is a service to run, monitor, and hand to a junior developer. Adopting one early is the most likely way this project stalls.

Should an analytical warehouse ever be needed, the move is deliberately cheap: dlt supports many destinations first-class, and dbt models written for `dbt-postgres` port with contained SQL changes. Write modeling code that does not depend on warehouse-specific features.

## Non-negotiable rules

1. **ELT, never ETL.** Raw preserves the source payload as received. Business logic lives only in dbt.
2. **All SmartMoving API calls go through `scripts/sm_client.py`.** Never ad-hoc curl, never a second client. This is the mechanism that prevents duplicate extraction across teams.
3. **SmartMoving quota is 125,000 calls/month.** Prefer reprocessing from raw over re-calling the API. Every call is logged to `scripts/api_call_log.jsonl`.
4. **Single database, `entity_id` on every table, Row-Level Security.** Never separate schemas or databases per company.
5. **Composite primary keys, merge write disposition, idempotent loads.** Every load must be safely re-runnable.
6. **No consumer reads `raw_*` or `core`.** Other teams read `serving` only.
7. **Never store a naked source identifier.** Business keys are always `(entity_id, external_id)`.
8. **Every timestamp is `timestamptz` in UTC.** No exceptions.

## Data layers

| Schema                                 | Contents                                                                                         | Who reads it              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------- |
| `raw_smartmoving`, `raw_quickbooks`, ... | Source payloads as received, dlt-loaded, merged on composite PK                                  | dbt only                  |
| `staging`                              | dbt views: renamed, typed, lightly cleaned. One model per raw table.                             | dbt only                  |
| `core`                                 | Canonical, cross-source-resolved entities: `employees`, `branches`, `jobs`, `customers`, `calls` | dbt only                  |
| `marts`                                | Analytical models for BI. May change whenever an analyst needs it.                               | Metabase, analysts        |
| `serving`                              | Stable, versioned, documented views. The public contract.                                        | Other teams' applications |

`marts` and `serving` differ in exactly one way that matters: `marts` changes freely, `serving` cannot change without a version bump and a deprecation window.

Where a source schema is volatile, preserve the full payload in a `JSONB` column alongside the normalized fields so reprocessing never requires an API call.

## Conventions

### Naming

- `snake_case`; plural table names, singular column names
- Raw schemas prefixed `raw_<source>`
- dbt models: `stg_<source>__<entity>`, `int_<description>`, `dim_<entity>`, `fct_<event>`
- Serving views: `serving.<entity>_v1` - the version suffix is mandatory

### Identifiers

- `entity_id` on every table, including raw
- Business keys are `(entity_id, external_id)`, never `external_id` alone
- Surrogate keys are generated in dbt, never in the pipeline

### Time

- Store every timestamp as `timestamptz` in UTC
- Branch-local timezone lives in `core.branches.timezone` as an IANA name (e.g. `America/Chicago`)
- Convert to local time only in the presentation layer, or in a column explicitly suffixed `_local`
- Every `serving` view carries `synced_at timestamptz` so consumers can display data freshness

### Identity resolution

- Employee identity is anchored on the Paylocity Employee ID
- Cross-source matches live in explicit crosswalk tables, never inferred at query time
- An unmatched record is surfaced for review, never silently dropped

## Serving contracts

This is the deliverable other teams depend on. A `serving` view is not finished until all of the following exist:

- An entry in `serving_catalog.md`: contents, source systems, grain, freshness target, owner
- `entity_id` and `synced_at` columns present
- dbt tests: not-null on keys, uniqueness on the declared grain, referential integrity to `core`
- A version suffix

**Change policy.** Additive changes (adding a column) ship freely. Breaking changes (rename, type change, removal) require a new version, with the previous version kept live for 90 days.

**Access policy.** Consumers connect with a read-only role scoped to `serving`, enforced by RLS on `entity_id`. No consumer receives credentials to `raw_*` or `core`. Any team that finds itself wanting to call a vendor API directly should be given a serving view instead - that request is a signal the catalog has a gap.

## Freshness targets

Published, monitored targets - not aspirations. Extend this table as sources are added.

| Source      | Entity               | Mechanism                    | Target   |
| ----------- | -------------------- | ---------------------------- | -------- |
| SmartMoving | Opportunities / jobs | Webhook + windowed polling   | < 15 min |
| SmartMoving | Leads                | Webhook + windowed polling   | < 15 min |
| SmartMoving | Dimensions           | Scheduled daily pull         | < 24 h   |
| SmartMoving | Scheduled reports    | File/email ingestion via n8n | < 24 h   |

**Webhooks provide freshness; polling provides correctness.** Never rely on webhooks alone - they drop, arrive out of order, and replay. Every webhook-fed entity must also have a reconciling poll. Webhook handlers must be idempotent and must write to raw before any processing.

## Adding a new source

Follow this order. Skipping steps produces sources that each behave differently and cost more to maintain than they save.

1. Document the API under `<source>_api_docs/` - endpoints, auth, rate limits, pagination
2. Add a client under `pipeline/` with call logging and a budget, mirroring `sm_client.py`
3. Define the dlt extraction resource with composite PK and merge disposition
4. Land into `raw_<source>` with no transformation
5. Write `stg_<source>__*` models
6. Extend `core` entities and crosswalk tables
7. Publish `serving` views only when a consumer needs them
8. Add the source to the freshness table above

## Data quality

- Every `core` and `serving` model has dbt tests. A model without tests does not ship.
- For webhook-fed entities, a scheduled reconciliation job compares webhook-derived state against a polled snapshot and alerts on divergence.
- Row-count and freshness checks run after every load. Failures alert; they never pass silently.
- `smartmoving_api_findings.md` is ground truth over the scraped docs wherever they conflict.

## Repository layout

- `smartmoving_sync_strategy.md` - CDC/freshness design for SmartMoving: webhooks + window-based polling + scheduled-report ingestion, per-entity mechanisms, quota budget, phased rollout. Read before any ingestion work.
- `decisions/` - ADR log: settled architecture decisions (Postgres as the store, instance- entity, hybrid serving+core access, n8n-not-Dagster) so they are not re-litigated.
- `serving_catalog.md` - the published catalog of `serving` views. The contract other teams read. Keep current; a view that is not catalogued does not exist.
- `consuming_serving_data.md` - the guide for app teams: how to connect with the read-only `app_read` role, what RLS/`entity_id` scoping means, reading `synced_at`, and the versioning/deprecation policy.
- `dbt/` - the dbt project (`dbt-postgres`): `staging` -' `core` -' `marts` -' `serving`. Layer schemas are literal (see `macros/generate_schema_name.sql`). Run with the repo `.env` exported as `POSTGRES_*`: `cd dbt && dbt build --profiles-dir .`. After every build run `sql/10_apply_rls.sql`.
- `sql/` - Postgres bootstrap (`00_bootstrap.sql`: schemas, roles, RLS control table) and `10_apply_rls.sql` (grants + RLS on core/serving, run after every dbt build). See `sql/README.md`.
- `smartmoving_api_docs/` - scraped reference for the SmartMoving External API (65 endpoints, base URL `https://api-public.smartmoving.com/v1`). Organized by category (`basic/`, `opportunities/`, `leads/`, etc.), each with `README.md` + `endpoints.json`; `openapi.yaml` is generated from these by `generate_openapi.py` (regenerate with `python smartmoving_api_docs/generate_openapi.py`). Endpoints under `/api/premium/` require the paid Premium API.
- `smartmoving_*.md` (root) - condensed AI-context guides for the SmartMoving API, lead API, and webhooks; `smartmoving_api_complete_reference.md` is the exhaustive version; `smartmoving_api_findings.md` is ground truth from live API exploration (real enum values, volumes, PageSize cap of 200) - trust it over the scraped docs where they differ.
- `pipeline/` - the dlt extraction pipeline: `run.py` CLI extracts leads/jobs-window/dims from both instances into DuckDB (dev) or Postgres (prod). Read `pipeline/README.md` before touching it - it records non-negotiable design rules (composite PKs, merge-everywhere, entity-local dates) and a dlt config-injection gotcha.
- `scripts/sm_client.py` - back-compat shim re-exporting the SmartMoving API client from `pipeline/sm_pipeline/client.py` (reads `.env`, logs every call to `scripts/api_call_log.jsonl`, enforces a per-session call budget). Always use it for API calls; never ad-hoc curl. See the `smartmoving-api` project skill.
- `SCRDLA - dim_*.csv` - hand-maintained seed dimension mappings (future dbt seeds): status -' boolean flags (`is_booked`, `is_lost`, etc.), line-of-business classification rules (rule/priority-based; service_type is reliable, branch_name is not), referral-source -' marketing-channel mapping, and sales-team assignments. Column notes inside these CSVs encode business rules - preserve them when editing.
- `smartmoving_scheduble_reports/` - sample xlsx/csv exports of SmartMoving's schedulable reports, useful as ground truth for field names and expected report shapes.

## Roadmap

**Phase 1 - SmartMoving -' Postgres (current)**
Extraction running on schedule; `raw_smartmoving` populated; `core` entities modeled; first `serving` views published and catalogued; one Google Sheet retired.

**Phase 2 - Remaining sources**
QuickBooks, Paylocity, RingCentral, marketing tools. Crosswalk tables complete. Remaining Google Sheets retired.

**Phase 3 - Applications**
Other teams build against `serving`. Access and change policies enforced in practice, not just documented.

**Phase 4 - Analytical offload**
Adopt a columnar analytical warehouse only if the trigger above fires.

## Working conventions

- Some content (CSV header notes, parts of docs) is in Spanish; keep the language of the file being edited. This file and all code stay in English.
- Files live in OneDrive - avoid creating large temporary files in the repo; use the scratchpad.
- Secrets live in `.env` and never in the repository. Connection strings and API keys are never hardcoded, never logged.
