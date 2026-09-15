# SmartMoving warehouse: extraction pipeline (Phase 1)

API extraction with dlt from the two SmartMoving instances. This package implements
the polling, sweep, targeted enrichment and quote-resolution portions of the live
warehouse. The other two ingestion paths are also live but intentionally use n8n
instead of dlt: webhooks are persisted directly before the receiver answers HTTP 200,
and emailed reports are downloaded, verified and landed directly as JSONB.

All Jobs has a special producer: `pipeline/report_bot` controls the SmartMoving web
application with Playwright, selects the report window and clicks **Run Report** so
SmartMoving sends the email. The bot does not download or load the report; the common
`report_ingest` workflow owns everything after the email arrives.

## Run

```bash
cd pipeline
python -m venv .venv
.venv\Scripts\Activate.ps1  # Windows
pip install -r requirements.txt

python run.py --job all --dest duckdb          # local smoke test
python run.py --job all --dest postgres        # production destination, if env vars are set
python run.py --job leads --instance local     # today's leads only, one instance
python run.py --job leads --leads-from 20260601 --leads-to 20260718 --instance all   # leads backfill
python run.py --job jobs --days-ahead 30       # thin sweep (customer -> opp -> job), +N day window
python run.py --job enrich --instance all      # sweep + full enrichment for changed opps
python run.py --job enrich --sweep-only --instance all   # sweep ONLY - crosswalk, no detail calls
python run.py --ids 1a2b,3c4d --instance ld    # targeted enrichment for concrete ids (webhook worker)
```

Typical cost of `--job all --instance all`: **~30 calls** logged in `../scripts/api_call_log.jsonl`.

### `--job enrich` - the "All Jobs"-style detail layer (Path 1 body)

The cheap `/api/customers?IncludeOpportunityInfo` sweep over `[today+from_offset, today+to_offset]` is the **change detector** (window defined in [`crm_sync_contract.md`](../crm_sync_contract.md), enforced by `scripts/check_sync_contract.py`). Only opportunities that changed or went stale receive the expensive `GET /api/opportunities/{id}` call with **all 10 `Include*` flags** (estimates, origin/destination addresses, rates/charges, payments, trip info, documents; they do not cost extra quota). It lands in `raw_smartmoving.opportunities_enriched` plus child tables such as `__jobs`, `__jobs__estimated_charges`, `__jobs__job_addresses`, and `__payments`.

#### Three change detectors, because no single one is sufficient

1. **Sweep hash.** A signature of *everything* the sweep returns for an opportunity. Cheap and immediate.
   **It is structurally blind to money and to the custom `leadStatus`** — the sweep returns only
   `{id, quoteNumber, status}` and `{job id, jobNumber, serviceDate, type}`. A re-quote, a charge edit, a
   payment, or `leadStatus` moving CMET -> Booked produces an identical hash. No widening can fix this;
   do not try.
2. **Staleness TTL.** Bounded blindness. `--hot-ttl-hours` (default 24) refreshes opportunities with a
   service date in `[today-3, today+21]`; `--cold-ttl-hours` (default 336 = 14 d) is the safety net for
   the rest of the window. Tiered on purpose: a flat 24 h TTL over the whole sweep window would cost
   an order of magnitude more than the whole budget allows. `--refresh-stale-hours N` forces anything
   older than N hours.
3. **Report-driven queue.** `marts.mart_enrichment_candidates`, fed by the daily zero-quota reports,
   targets exactly the opportunities whose money or status the sweep cannot see. This is the real fix
   for detector 1's blind spot.

#### State schema (`dlt` source state, persisted in the destination)

```
st["opps"][<opportunity id>] = {
    "h":    sweep hash of the last successful enrichment
    "t":    ISO timestamp of that enrichment   (drives the TTL)
    "seen": ISO timestamp of the last sighting (drives deletion detection)
    "sd", "sdx": min/max service date YYYYMMDD (which sweep windows could see it)
    "ls":   last known trimmed leadStatus
    "gone", "gp", "g404": soft-delete marker, pending-emit flag, 404 origin
}
st["sweep"] = {"at": ISO, "from": YYYYMMDD, "to": YYYYMMDD}   # last COMPLETED sweep
```

Migrated automatically from the old `{opp_hashes, seen_ids, prior_ids}` layout on first run, seeding
`t` to now so the upgrade does not re-enrich the whole window at once.

#### Soft-delete

Recorded in `raw_smartmoving.opportunity_deletions`; raw never physically deletes, and a later enriched
snapshot revives the opportunity in dbt. Two independent triggers:

- **`detail_404`** — the detail endpoint returned 404. Direct proof, immediate. This is the path an
  `opportunity-deleted` webhook takes.
- **`sweep_disappearance`** — a **completed** sweep whose window could have reached the opportunity did
  not return it.

> **Do not reintroduce a within-run presence diff.** dlt extracts resources **round-robin, interleaved** —
> a resource yielded last can and does run before the sweep next to it has finished. Deletion is
> therefore evaluated against the last sweep *recorded as complete in state*, which is correct whether
> this resource runs early (detection lands next run) or late (immediate). Absence is also ignored for
> opportunities whose service span falls outside the sweep window, because the window slides daily.
> An ungated diff marks every opportunity that merely aged out as deleted. Every schedule now uses the
> SAME window (see the contract) precisely so two schedules cannot disagree about what absence means.

- **Initial seed (one time):** `python run.py --job enrich --dest postgres` with `local`. Because all opportunities are "new" the first time, it enriches the whole window; budget accordingly with `--budget`. Prefer `--sweep-only` first: it builds the crosswalk cheaply and lets the staleness TTL absorb the detail calls gradually (see [`crm_sync_contract.md`](../crm_sync_contract.md)). Later runs only touch changes.
- `--ids ...` skips the sweep and enriches concrete ids. This is what the webhook worker (Path 1) invokes after debounce. A 404 on one id no longer kills the batch.

## Destinations

- **duckdb (default):** `~/.smartmoving_dw/warehouse.duckdb` (intentionally outside OneDrive). Used for local development and validation. The file name must not match the dataset (`raw_smartmoving`) because DuckDB does not disambiguate catalog vs schema.
- **postgres (`--dest postgres`) - production destination.** The central store (DO Managed Postgres). Before running it, apply `../sql/00_bootstrap.sql` (schemas + roles + RLS). Provide credentials through standard dlt variables in `.env` or the environment:
  - `DESTINATION__POSTGRES__CREDENTIALS=postgresql://platform_rw:PASSWORD@HOST:PORT/DBNAME`
  - Or discrete fields: `DESTINATION__POSTGRES__CREDENTIALS__HOST`, `__USERNAME`, `__PASSWORD`, `__DATABASE`, `__PORT`
  - dlt loads into `raw_smartmoving.*`; dbt builds `staging`/`core`/`marts`/`serving` on top.

## Ad platforms: `run_ads.py` (Phase C)

A second CLI, not a `--job` here, because none of `run.py`'s SmartMoving flags apply.
Same rules: `.env` only, every call in `scripts/api_call_log.jsonl`, `--budget`,
composite PK + merge.

```
python run_ads.py --platform google_ads --list-accounts                 # the manager's tree, no load
python run_ads.py --platform google_ads --dest postgres                  # last 30 days, every child account
python run_ads.py --platform google_ads --dest postgres --from 2023-01-01 --to 2023-12-31
python run_ads.py --platform google_ads --dest postgres --account 1234567890 --from 2023-01-01
```

- **Manager -> children.** Auth is a service account added as a user of the Google Ads
  MANAGER; children are discovered on every run, so a new account needs no code change -
  only a one-off `--from 2023-01-01 --account <id>` backfill. Every row carries the
  child's `account_id`, and it is in the PK.
- **Window, not cursor.** Default re-reads the last 30 days; Google restates recent cost.
  Backfills are chunked in 92-day pieces.
- Access level: until the developer token has Explorer/Basic access, every read beyond
  `--list-accounts`'s first line fails with `CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION`.
  That is Google's gate, not a bug. See `marketing_ads_integration_guide.md` §2.

## Design (non-negotiable decisions)

- **Raw = API shape.** dlt normalizes nested data into child tables (`customers_service_window__opportunities__jobs`...) without loss. The wide "everything" row is a later dbt model, never built here.
- **Composite PK (`source_instance_id`, `id`)** everywhere: GUIDs are only unique per instance. Each row also carries `entity_id` and `_sm_extracted_at`.
- **`write_disposition="merge"` everywhere** (including dimensions): running twice never duplicates; each instance loads separately without overwriting the other. A `replace` here would erase rows from the other instance, a bug already made and fixed.
- **"Today" = local date** for API windows (the extraction uses the default timezone in `instances.py`; dbt's timezone authority is `core.branches.timezone`), never UTC.
- **Run budget** (`--budget`, default 300): the client stops if a job runs away; every request is written to the ledger.

## dlt gotcha learned the hard way

dlt injects configuration into **resource function arguments**: an argument named `path` resolves from the `PATH` environment variable. Never pass state through defaulted resource arguments; use closures through a factory function instead (see `_make_dim` in `sm_pipeline/source.py`).

## Implementation status

1. Done. Local seed: `leads`, `customers_service_window`, dims in duckdb.
2. Done. Postgres bootstrap (`sql/00_bootstrap.sql`) + dlt destination env + first `--dest postgres` run.
3. Done. Diff-driven opportunity enrichment (`--job enrich`): customers sweep + `GET /api/opportunities/{id}` with all 10 `Include*` flags -> `raw_smartmoving.opportunities_enriched`.
4. Done. Direct n8n landing DDL: `../sql/20_webhook_events.sql` (Path 1) and `../sql/30_report_landing.sql` (Path 3).
5. Done. n8n webhook receiver -> `raw_smartmoving.webhook_events` + debounced, allowlisted enrichment worker invoking `run.py --ids ...`.
6. Done. n8n extraction and dbt schedules are defined operationally; Dagster remains deferred by `decisions/0004`. Cadence is defined only in [`crm_sync_contract.md`](../crm_sync_contract.md) section 6.
7. Done. `report_ingest` resolves report metadata from the email, downloads the XLSX, preserves empty cells, lands JSONB, verifies the vendor-stated row count and triggers dbt.
8. Done. `report_bot_all_jobs` uses Playwright browser control to request All Jobs emails because that report cannot be scheduled natively.
9. Open. Schedule the budgeted `quote_backfill` drain in n8n; until then it is run manually.
