# sql/ - Postgres bootstrap & RLS

Plain SQL run against the central Postgres store. No ORM, no migrations tool yet (Phase 1 is small enough not to need one).

## Run order

1. **`00_bootstrap.sql`** - once, as DB admin/superuser. Creates schemas (`raw_smartmoving`, `staging`, `core`, `marts`, `serving`), the `platform_rw` and `app_read` roles, grants, and the `core.entity_access` map that RLS keys on. Idempotent.
   - Then set role passwords out-of-band (not in any file):
     `ALTER ROLE platform_rw LOGIN PASSWORD '...'; ALTER ROLE app_read LOGIN PASSWORD '...';`
   - Put the `platform_rw` connection string in `.env` as `DESTINATION__POSTGRES__CREDENTIALS` for dlt/dbt.

2. **`20_webhook_events.sql`** and **`30_report_landing.sql`** - once, as DB admin. Create the raw landing tables written **directly by n8n** (not dlt): the webhook receiver's append-only event log (Camino 1) and the Scheduled-Reports landing (Camino 3). Both are `raw_smartmoving.*`, platform-only, no `app_read` access. Idempotent. See each file's header for the design (dedupe, `report_generated_at` precedence).

3. Load raw (`pipeline/run.py --dest postgres`) and build models (`dbt build`).

4. **`10_apply_rls.sql`** - after **every** `dbt build`. dbt drops/recreates tables, which drops their RLS policies, so re-run this to re-secure every `core` + `serving` table (enables RLS + a policy keyed on `core.entity_access`). Idempotent. A dbt `on-run-end` hook can call it automatically later.

## Access model (decisions/0003)

- `platform_rw` owns everything and bypasses RLS by design (dlt + dbt use it).
- `app_read` (or a per-team role that inherits it) may `SELECT` on `serving` + `core` only - never `raw_*`/`staging`, never a vendor API key. RLS filters it to the entities listed for its role name in `core.entity_access`.
- To onboard a consumer for an entity: `INSERT INTO core.entity_access(role_name, entity_id) VALUES ('their_role', 'their_entity');`
