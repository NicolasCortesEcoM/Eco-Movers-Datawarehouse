# 0001 - Central store is PostgreSQL

**Status:** Accepted (July 2026) - Supersedes the earlier warehouse-first research that assumed a separate analytical warehouse.

## Decision

The central data store is a single **PostgreSQL** database holding all layers (`raw_*`, `staging`, `core`, `marts`, `serving`). A separate columnar/analytical warehouse is **out of scope for now**.

## Why

- The immediate need is a **real database that serves applications**, not an analytical warehouse. Everything today lives in Google Sheets; the data volume is small.
- Postgres gives transactional serving, row-level security, and a connection model that internal apps already know how to consume.
- Adopting an analytical warehouse now would add a service to run, monitor, and hand to a junior - the most likely way to stall the project.

## When to revisit (the trigger)

Consider a columnar analytical warehouse only when **analytical queries degrade application performance even on a read replica**, or **history outgrows what an operational database should carry**. The move is kept cheap by design: dlt supports many destinations first-class, and `dbt-postgres` models port with contained SQL changes - **so modeling code must not depend on warehouse-specific features.**

## Consequences

- The pipeline's destination is `postgres` (`pipeline/run.py --dest postgres`); `duckdb` is dev-only.
- `smartmoving_sync_strategy.md` targets Postgres/n8n; the architecture doc keeps a header banner marking it historical.
