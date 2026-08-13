# Consuming serving data (for app teams)

How to read the central data platform from your application. You never call a vendor API, and you never touch `raw_*`, `staging`, or `marts` - you read the `serving` schema (and, if you need it, `core`).

## What you connect to

- A single PostgreSQL database, schema **`serving`** - the stable, versioned, documented contract. Everything in it is catalogued in `serving_catalog.md`.
- You connect with the read-only role **`app_read`** (or a per-team role that inherits it). Ask the platform team for the connection string; credentials live in a secret store, never in code.

```
host=<managed-postgres-host>  port=5432  dbname=datawarehouse
user=app_read                  sslmode=require
```

## What you can and cannot read

| Schema | Access | Notes |
|---|---|---|
| `serving` | -... read | The contract. Start here. Versioned; changes are announced. |
| `core` | -... read (**unstable**) | Canonical entities. Handy for app-specific needs, but **may change without a version bump** - if a `core`-based query becomes load-bearing, ask for a `serving` view instead. |
| `marts`, `staging`, `raw_*` | - blocked | BI / internal only. Not part of any contract. |

## Row-Level Security - you only see your own entity

Every row carries an `entity_id`. RLS filters your role to the entities it's authorised for, enforced in the database - you physically cannot read another entity's rows, no `WHERE` clause required. If you get fewer rows than expected, that's RLS doing its job; contact the platform team if your entity mapping needs changing.

## Reading freshness

Every serving view carries **`synced_at`** - when that row's source data was last extracted. Show it in your UI ("as of 10:42"). Don't assume real-time.

`synced_at` is the truth for a given row. The *target* your view is held to lives in `crm_sync_contract.md` section 8, named per entity from `serving_catalog.md` - so a target is stated once and cannot go stale in two places. If `synced_at` is consistently further behind than the target, tell the platform team; that is a pipeline problem, not something to work around in your app.

## Versioning & change policy

- Views are suffixed `_v1`, `_v2`, ... The suffix is part of the name you query.
- **Additive** changes (a new column) appear in place - safe.
- **Breaking** changes (rename, type change, removal) ship as a **new version**; the old one stays live for **90 days**. Migrate within that window.
- Want a field that isn't there? That request is how the catalog grows - ask the platform team. Do **not** work around a gap by calling the vendor API yourself.

## Example

```sql
-- Upcoming operations jobs for the next 3 days
select service_date, job_number, service_type_name, customer_name, status, synced_at
from serving.jobs_upcoming_v1
where days_until_service <= 3
order by service_date, customer_name;
```
