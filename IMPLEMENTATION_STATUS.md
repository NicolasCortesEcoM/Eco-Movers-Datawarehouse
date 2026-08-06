# Implementation Status - living guide

> **How to use this document.** This is the map of where we are, what is missing, and what comes next.
> Whenever something is completed, mark it (`[x]`) and add the date. The **Next immediate step**
> always reflects the next action. Architecture documentation lives in `CLAUDE.md`,
> `smartmoving_sync_strategy.md`, and `decisions/`; this file is the progress board.

**Current phase:** Phase 1 - SmartMoving -> Postgres.
**Last updated:** 2026-08-05.

---

## Next Immediate Step

**Repository is about to move to Azure/GitHub** (`https://github.com/NicolasCortesEcoM/Eco-Movers-Datawarehouse`). This must happen before anything else, since it's the first commit and mistakes there are permanent history:

0. **Push to GitHub.**
   - This folder has no git history yet (`.git/` is empty). Run `git init`.
   - `.gitignore` now excludes `smartmoving_scheduble_reports/` (live customer PII), `scripts/api_call_log.jsonl` (runtime log), `.playwright-mcp/` (browser snapshots), `dbt/target/`, `dbt/logs/`, `dbt/.user.yml`, and `**/__pycache__/` — these were left on disk, not deleted, but must never be committed. Confirm `.env` is ignored.
   - All droplet/SSH/webhook values that used to be hardcoded in docs (`deploy/README.md`, this file, `smartmoving_sync_strategy.md`, `smartmoving_api_findings.md`) are now placeholders — real values live only in `.env` (`droplet_ssh_host`, `droplet_ssh_user`, `n8n_docker_gateway`, `smartmoving_webhook_url`, `reporting_webhook_url`). Verify no document still has a literal IP, hostname, or webhook URL before committing.
   - Run `git status` and review the full file list once staged, then `git add`, commit, `git remote add origin https://github.com/NicolasCortesEcoM/Eco-Movers-Datawarehouse.git`, and push.

**The enrichment orchestration layer is already built** (dbt status ledger + n8n worker + schedules). One manual step is still required to turn it on because n8n runs in Docker without Python, while the pipeline must live on the droplet host:

1. **Deploy the pipeline on the droplet host** (`/opt/datawarehouse`). The bundle is ready in [deploy/](deploy/). Follow [deploy/README.md](deploy/README.md): `scp` `pipeline/` + `scripts/` + `.env`, then run `bash host_bootstrap.sh` to create the venv, install packages, and smoke test. You type the SSH password because there is no key auth.
2. **Confirm the n8n SSH credential.** n8n auto-assigned the only existing credential, `SSH Password account` (id `1wkrc8PhMPB14wEp`). Verify that it points to the **droplet host** (`<n8n_docker_gateway>:22`, `<droplet_ssh_user>` — values in laptop `.env`); otherwise edit it or create a new one and reassign it in the 5 workflows.
3. **Publish the 6 workflows** (currently drafts so they do not fail before deployment): `Enrichment_worker`, `leads_poll`, `opps_sweep`, `weekly_dims`, `nightly_reconciliation`.
4. **Reports (Path 3):** `sql/31_report_booked_lost.sql` has already been applied. The remaining work is the n8n IMAP flow plus SmartMoving report schedules. I need the ingestion mailbox (IMAP host/credentials) and one sample email for each report to map columns.

Minor pending items already resolved by the user: `pg_hba.conf` dedupe and the `x-sm-instance` typo.

> The warehouse is already **migrated and live on the droplet**. Local access for continued work: SSH tunnel in **Windows PowerShell** (not WSL), `ssh -L 5433:localhost:5432 <droplet_ssh_user>@<droplet_ssh_host>` (values in laptop `.env`: `droplet_ssh_user`, `droplet_ssh_host`); the laptop connects to `127.0.0.1:5433`.

---

## Connection Architecture (established 2026-07-22)

- **Droplet:** address in laptop `.env` as `droplet_ssh_host`, hostname `n8n`. **Postgres and n8n live on the same machine**. n8n reaches Postgres through `localhost` from the host side, with no tunnels and no public database port.
- **Dedicated database:** `datawarehouse`, separate from the overtime app DB and others. Isolation is at database level, not schema level. Schemas: `raw_smartmoving`, `staging`, `core`, `marts`, `serving`.
- **Roles:** never connect apps as `postgres` or superuser.
  - `platform_rw` - dlt + dbt. Owner of everything inside `datawarehouse`; connects on the droplet.
  - `app_read` - consumer apps. `SELECT` only on `serving` + `core`, with RLS by `entity_id`.
  - **Rule:** one role per access pattern, not per app. Two apps that only read `serving` share `app_read`; entity isolation comes from RLS (`core.entity_access`). Create a new role only when permissions differ.
  - Existing droplet apps with their own user/schema are untouched. If they become warehouse sources later, ingest them as `raw_<source>` rather than cohabiting.
- **Laptop access:** use an SSH tunnel; do not open port 5432. The droplet's 5432 stays closed externally:
  ```bash
  ssh -L 5433:localhost:5432 <droplet_ssh_user>@<droplet_ssh_host>
  # values in laptop .env: droplet_ssh_user, droplet_ssh_host
  # with the tunnel open, the laptop connects to localhost:5433 -> droplet Postgres
  ```
- **Backups:** pending and early priority. Self-hosted on the droplet means backups are our responsibility. A daily `pg_dump` to DO Spaces/S3 is enough for Phase 1. If the droplet dies without a backup, the warehouse is lost.
- **n8n runs in Docker; Postgres runs natively on the host.** Docker `localhost` points to the container, not the host.
  - n8n network: `n8n-docker-caddy_default`, gateway in laptop `.env` as `n8n_docker_gateway` (verify with `docker inspect`; each install can differ).
  - Postgres already listened on `0.0.0.0:5432`.
  - Required access: `ufw allow from 172.18.0.0/16 to any port 5432 proto tcp`, plus one `pg_hba.conf` line per role: `host datawarehouse <role> 172.18.0.0/16 scram-sha-256`. The droplet runs PG 14.
  - n8n credential `Datawarehouse Postgres`: Host = `<n8n_docker_gateway>`, not `localhost`.
  - `ot-project-db-1` is the overtime project Postgres 16 container and is completely separate from `datawarehouse`. Do not touch or relate it.

---

## Completed

### RAW Layer + Enrichment (validated end-to-end in local Postgres)
- [x] dlt extraction: `leads`, `customers_service_window` (thin sweep), 11 dimensions - `pipeline/sm_pipeline/source.py`
- [x] **Diff-driven enrichment** `--job enrich`: `[-7,+30]` sweep as change detector -> only changed opportunities call `GET /api/opportunities/{id}` with all 10 `Include*` flags. Output: `raw_smartmoving.opportunities_enriched` plus child tables.
- [x] dlt-state watermark persists in the destination; unchanged reruns cost only the sweep, 0 enrichment calls.
- [x] Targeted enrichment `--ids a,b,c` (no sweep), the webhook worker entrypoint.
- [x] Soft-delete for disappeared opportunities -> `raw_smartmoving.opportunity_deletions`; raw never physically deletes.
- [x] 429 rate-limit handling in `sm_client.py` with `Retry-After` retry plus proactive `pace` around 1.6 calls/sec.
- [x] Local Postgres seed: **178 ld opps + 479 local opps**, all with estimates; 1,458 charges, 1,469 addresses, 41 payments.
- [x] Idempotency verified: ld rerun = 2 calls (sweep only), 0 duplicates.

### Landing Tables (DDL applied in local Postgres)
- [x] `sql/20_webhook_events.sql` - append-only webhook log + deadletter (Path 1), dedupe by hash.
- [x] `sql/30_report_landing.sql` - `report_all_jobs`, precedence by `report_generated_at`, JSONB fidelity (Path 3).

### Transformations + Contracts
- [x] dbt: staging -> core (`jobs`, `leads`) -> serving. 34/34 tests green.
- [x] `serving.jobs_upcoming_v1` and `serving.leads_today_v1` published and cataloged.
- [x] RLS by `entity_id` (`sql/10_apply_rls.sql`), cross-entity isolation verified.

### Droplet - Migrated And Live (2026-07-22)
- [x] `datawarehouse` database created; `sql/00_bootstrap.sql` applied.
- [x] `platform_rw` and `app_read` created with passwords; both connect successfully.
- [x] Laptop -> droplet SSH tunnel verified in Windows PowerShell.
- [x] **Local -> droplet migration via Python/psycopg2** because `pg_dump` was unavailable: 34 `raw_smartmoving` tables, **18,637 rows**, API quota = 0. dlt state preserved. Droplet runs **PG < 15**, so `NULLS DISTINCT` was removed from reflected DDL.
- [x] `sql/20` + `sql/30` landing scripts applied on the droplet.
- [x] `dbt build` on the droplet: **34/34 green**; `serving.jobs_upcoming_v1` = 641 rows.
- [x] `sql/10_apply_rls.sql` on the droplet; made resilient so redundant non-owner GRANTs are skipped. RLS active on core jobs/leads and serving; `app_read` reads filtered serving+core and cannot read `raw_*`.
- [ ] Point `.env` (`postgres_*`) to the droplet through the tunnel for the next pipeline runs.
- [ ] Daily `pg_dump`/backup to Spaces/S3.

### n8n Webhook Log - Live (2026-07-22)
- [x] n8n `Datawarehouse Postgres` credential created (host `<n8n_docker_gateway>`, value in laptop `.env`).
- [x] New workflow `Reporting_datawarehouse` (id `KswuBX6pyuAAziEj`). The old `Cancelled Opportunity` workflow (`fSs1rIV9Ik0m0824`) remains untouched and separate.
- [x] Both SmartMoving instances send 17 events to the reporting webhook (`reporting_webhook_url` in laptop `.env`) with custom headers `x-sm-instance: ld` / `x-sm-instance: local` plus shared `x-sm-secret`.
- [x] Flow: Webhook validates `x-sm-secret` -> Code extracts `event-type`, `resource_id`, and instance header (tolerates `x-sm-instace`) -> Postgres INSERT into `raw_smartmoving.webhook_events` with `skipOnConflict` on `dedupe_hash`.
- [x] Verified with real traffic: 160 events captured, both instances, multiple event types. API cost = 0.
- [x] Deduplicated `pg_hba.conf` on the droplet.
- [x] Corrected SmartMoving header to `x-sm-instance`.
- [x] Future integration with `Cancelled Opportunity` deferred; it stays independent.

### Enrichment Orchestration - Built As Drafts (2026-07-22)
Session decisions: execute from **n8n -> SSH to the droplet host**; enrich **only high-value events**; reports are **All Jobs + booked + lost**. Supporting data: 422 webhooks in ~25 min, around 1,000/hour; `opportunity-changed` = 73% noise; `local` has about 2,200 calls/day of remaining margin.

- [x] **Tier 0 - status ledger without API calls.** dbt `stg_smartmoving__webhook_opportunity_status` + `int_opportunity_status_latest` (marts/view). Latest status by opportunity from the webhook log. Build + 8 tests OK on the droplet. **136 live opps by status, API cost = 0.**
- [x] **Worker `Enrichment_worker`** (id `XPBsZoF7goshMuz8`) every 5 min: SELECT unprocessed high-value events -> Code debounces to distinct `--ids` by instance -> SSH `run.py --ids ... --budget 200` -> mark processed or deadletter after 5 attempts. A parallel branch drains low-value events without spending quota.
- [x] **Schedules** (SSH `run.py`, `--instance all`): `leads_poll` (id `lA0spX6AFyc3iNAg`, every 30 min), `opps_sweep` (id `eFQUiMawRkEMJoyX`, hourly, `enrich [-7,+30]`), `weekly_dims` (id `p6fjQ24sIBHRSWfM`, Sunday 03:00), `nightly_reconciliation` (id `Sve0TiQArFuEcAXX`, 02:00, leads `[-7,0]` + enrich `[-7,+45]`).
- [ ] Deploy the pipeline on the host, confirm SSH credential, and publish the 6 workflows.

### Reports (Path 3)
- [x] DDL `sql/31_report_booked_lost.sql` -> `report_booked_opportunities` + `report_lost_leads`, applied on the droplet with the same contract as `report_all_jobs`.
- [ ] n8n IMAP/Gmail flow: sender/subject filter -> xlsx/csv parser -> INSERT. Needs ingestion mailbox and sample email to map `row_key` and columns.
- [ ] Schedule All Jobs + Booked Opportunities + Lost Leads daily in the SmartMoving UI.

### Modeling The New Enriched Raw Data (next after raw, not now)
- [ ] `stg_smartmoving__opportunities_enriched` plus children (charges, addresses, payments).
- [ ] `int_*_observations` + "latest observation wins" in core (sync strategy section 12).
- [ ] Lead -> opportunity map in dbt; complete sweep `status` enum mapping (3/10/20/30/50).
- [ ] Enrich `serving.jobs_upcoming_v1` with additive enrichment columns, no version bump.

---

## Key Facts And Decisions

- **Quota:** 125k/month **per instance**. `local` was already around 45% from an existing app that should be retired; `ld` around 6%.
- **Short-window rate limit confirmed** around 120/min in addition to monthly quota; see `smartmoving_api_findings.md`.
- **No lead-created webhook:** leads always use polling. A lead that converts disappears from `/api/leads`, but continues as an opportunity through sweep + enrichment; raw keeps both halves.
- **Self-hosted droplet persistence** is correct for Phase 1: cheap, already available, small volume. Move to Managed Postgres only if the `CLAUDE.md` trigger happens: analytical queries compete with n8n or history outgrows the operational DB.
- **Audit workflow `Cancelled Opportunity`** (`fSs1rIV9Ik0m0824`) remains active and untouched, unrelated to `Reporting_datawarehouse`. It has API keys hardcoded in plaintext and should eventually use the existing n8n credentials `SM LD API` / `SM API LOCAL API`; this is pending and not urgent.
