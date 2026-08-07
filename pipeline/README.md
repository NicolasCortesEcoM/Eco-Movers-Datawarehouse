# SmartMoving warehouse: extraction pipeline (Phase 1)

Raw extraction with dlt from the two SmartMoving instances. Implements Path 2 from `../smartmoving_sync_strategy.md` (date-window polling); Path 1 (webhooks) and Path 3 (reports) are added in later phases.

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
python run.py --job enrich --instance all      # [-7,+30] sweep + full enrichment for changed opps
python run.py --ids 1a2b,3c4d --instance ld    # targeted enrichment for concrete ids (webhook worker)
```

Typical cost of `--job all --instance all`: **~30 calls** logged in `../scripts/api_call_log.jsonl`.

### `--job enrich` - the "All Jobs"-style detail layer (Path 1 body)

The cheap `/api/customers?IncludeOpportunityInfo` sweep over `[today+from_offset, today+to_offset]` (default `[-7,+30]`) is the **change detector**. Only opportunities that changed or went stale receive the expensive `GET /api/opportunities/{id}` call with **all 10 `Include*` flags** (estimates, origin/destination addresses, rates/charges, payments, trip info, documents; they do not cost extra quota). It lands in `raw_smartmoving.opportunities_enriched` plus child tables such as `__jobs`, `__jobs__estimated_charges`, `__jobs__job_addresses`, and `__payments`.

#### Three change detectors, because no single one is sufficient

1. **Sweep hash.** A signature of *everything* the sweep returns for an opportunity. Cheap and immediate.
   **It is structurally blind to money and to the custom `leadStatus`** — the sweep returns only
   `{id, quoteNumber, status}` and `{job id, jobNumber, serviceDate, type}`. A re-quote, a charge edit, a
   payment, or `leadStatus` moving CMET -> Booked produces an identical hash. No widening can fix this;
   do not try.
2. **Staleness TTL.** Bounded blindness. `--hot-ttl-hours` (default 24) refreshes opportunities with a
   service date in `[today-3, today+21]`; `--cold-ttl-hours` (default 336 = 14 d) is the safety net for
   the rest of the window. Tiered on purpose: a flat 24 h TTL over the whole window costs roughly
   42k calls/month on `local`. `--refresh-stale-hours N` forces anything older than N hours.
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
> opportunities whose service span falls outside the sweep window, because the window slides daily and
> `opps_sweep [-7,+30]` and `nightly_reconciliation [-7,+45]` disagree. An ungated diff marks every
> opportunity that merely aged out as deleted.

- **Initial seed (one time):** `python run.py --job enrich --dest postgres` with `local`. Because all opportunities are "new" the first time, it enriches the whole window; budget accordingly with `--budget` (see the quota section in the strategy). Later runs only touch changes.
- `--ids ...` skips the sweep and enriches concrete ids. This is what the webhook worker (Path 1) invokes after debounce. A 404 on one id no longer kills the batch.

## Destinations

- **duckdb (default):** `~/.smartmoving_dw/warehouse.duckdb` (intentionally outside OneDrive). Used for local development and validation. The file name must not match the dataset (`raw_smartmoving`) because DuckDB does not disambiguate catalog vs schema.
- **postgres (`--dest postgres`) - production destination.** The central store (DO Managed Postgres). Before running it, apply `../sql/00_bootstrap.sql` (schemas + roles + RLS). Provide credentials through standard dlt variables in `.env` or the environment:
  - `DESTINATION__POSTGRES__CREDENTIALS=postgresql://platform_rw:PASSWORD@HOST:PORT/DBNAME`
  - Or discrete fields: `DESTINATION__POSTGRES__CREDENTIALS__HOST`, `__USERNAME`, `__PASSWORD`, `__DATABASE`, `__PORT`
  - dlt loads into `raw_smartmoving.*`; dbt builds `staging`/`core`/`marts`/`serving` on top.

## Design (non-negotiable decisions)

- **Raw = API shape.** dlt normalizes nested data into child tables (`customers_service_window__opportunities__jobs`...) without loss. The wide "everything" row is a later dbt model, never built here.
- **Composite PK (`source_instance_id`, `id`)** everywhere: GUIDs are only unique per instance. Each row also carries `entity_id` and `_sm_extracted_at`.
- **`write_disposition="merge"` everywhere** (including dimensions): running twice never duplicates; each instance loads separately without overwriting the other. A `replace` here would erase rows from the other instance, a bug already made and fixed.
- **"Today" = local date** for API windows (the extraction uses the default timezone in `instances.py`; dbt's timezone authority is `core.branches.timezone`), never UTC.
- **Run budget** (`--budget`, default 300): the client stops if a job runs away; every request is written to the ledger.

## dlt gotcha learned the hard way

dlt injects configuration into **resource function arguments**: an argument named `path` resolves from the `PATH` environment variable. Never pass state through defaulted resource arguments; use closures through a factory function instead (see `_make_dim` in `sm_pipeline/source.py`).

## Next Steps (in order)

1. Done. Local seed: `leads`, `customers_service_window`, dims in duckdb.
2. Done. Postgres bootstrap (`sql/00_bootstrap.sql`) + dlt destination env + first `--dest postgres` run.
3. Done. Diff-driven opportunity enrichment (`--job enrich`): `[-7,+30]` sweep + `GET /api/opportunities/{id}` with all 10 `Include*` flags -> `raw_smartmoving.opportunities_enriched`.
4. Done. Direct n8n landing DDL: `../sql/20_webhook_events.sql` (Path 1) and `../sql/30_report_landing.sql` (Path 3).
5. Pending. n8n webhook receiver -> `raw_smartmoving.webhook_events` + debounced enrichment worker invoking `run.py --ids ...`.
6. Pending. **n8n** schedules (Dagster deferred, `decisions/0004`): `leads` every 30 min, `enrich` every 60 min, `dims` weekly, nightly reconciliation.
7. Pending. Scheduled Reports IMAP flow -> `raw_smartmoving.report_all_jobs` and schedule the reports in the SmartMoving UI.
