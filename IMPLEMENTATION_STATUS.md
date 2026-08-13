# Implementation Status - the official project guide

> **How to use this document.** This is the single reference for where we are, what is missing, and
> what comes next. Whenever something is completed, mark it (`[x]`) and add the date. **Next Immediate
> Step** always reflects the next action. Architecture lives in `CLAUDE.md`,
> `smartmoving_sync_strategy.md`, and `decisions/`; this file is the progress board and the plan of record.

**Current phase:** Phase 1 - SmartMoving -> Postgres.
**Current workstream:** enriching **leads** and **opportunities** to the scheduled-report field set.
**Where that stands:** P0-P4 done; **P5 in progress** (Lead Status lands end-to-end; three reports and
their observation arms remain); **P6-P8 not started**. Detail in "Pending - the current workstream".
**Last updated:** 2026-08-13 (architecture audit - see below).
**Repository:** `https://github.com/NicolasCortesEcoM/Eco-Movers-Datawarehouse`

---

## Current Workstream - Scope

Enrich leads and opportunities with **addresses, emails, names, estimates**, and everything the
scheduled report workbooks carry. Raw stores payloads **exactly as received**; all typing and business
logic lives in dbt.

**Leads and opportunities are separate, independent records.** No lead -> opportunity join is built in
this phase. Note that the *lost-leads* report keys on `Quote #`, so despite its name it enriches
**opportunities**, not leads.

**Refresh cadence:** defined in [`crm_sync_contract.md`](crm_sync_contract.md) section 6. Webhooks carry near-real-time status at zero quota cost.

### Explicitly out of scope for now
Notes, follow-ups, customer interaction history, audit activity, inventory item lines, document URLs,
and Premium per-job calls. These are all reachable later; none is required for the field set above.

### Three facts that frame the work

1. **Leads are already maximally enriched by the API.** `GET /api/leads/{id}` returns byte-for-byte the
   same 28 fields as a list row - **never call it in a loop.** Name, email, phone, and both origin and
   destination street/city/state/zip already land in `raw_smartmoving.leads`. What remains is *modeling*,
   not extraction. Leads carry no money and no `quoteNumber`; that is an API limit, not a pipeline gap.
2. **`opportunities_enriched` and its 10 child tables are already in raw and completely unmodeled.**
   Estimates, charges, payments, job addresses, contacts, and the custom `leadStatus` are sitting in
   Postgres today with zero dbt models reading them. This is the largest available win at **zero API cost**.
3. **Quota is not the binding constraint.** The measured model in
   [`crm_sync_contract.md`](crm_sync_contract.md) section 7 lands at roughly 6% of the available
   calls. That buys *deeper* change detection, not less - and it is why the sweep window is wide.

---

## Working rule: the droplet is the environment

**We do not work locally.** Every structural change - a dbt model, a seed, a file in `sql/` - is
applied to the droplet in the same session it is made. Nothing is live for consumers yet, and the
point of the rule is that "going live" should be a permissions change rather than a migration.

One command does it:

```bash
python deploy/sync_droplet.py          # sync + dbt seed + build + test, under flock
python deploy/sync_droplet.py --sql    # also replay sql/*.sql (idempotent DDL)
```

See [deploy/README.md](deploy/README.md). **Evidence of completion must come from querying the
droplet**, not from a local build.

> The failure this prevents actually happened: on 2026-08-07 the report ingestion landed 4,801
> verified rows on the droplet while the droplet was still running the pre-Phase-2 dbt project.
> Everything was green locally and nothing there consumed the report.

---

## Droplet structural audit - 2026-08-08

Ran against the droplet, not local. Two blocking defects found, both fixed.

### FIXED - extraction was silently dead for 17 days

`platform_rw` had **no CREATE privilege on the database**. dlt's merge write disposition loads
through a transient staging dataset (`raw_smartmoving_staging`) that it creates per run, so
schema-level grants are not enough. Every extraction failed at the LOAD step with
`permission denied for database datawarehouse` - **after the API calls had already been spent**.
Quota burned, nothing landed.

Evidence it had been failing since 2026-07-22: `opportunities_enriched`, `leads` and every `dim_*`
table carried a 17-day-old `_sm_extracted_at`, while `webhook_events` (which n8n writes directly,
bypassing dlt) was current to the minute.

Fixed with `GRANT CREATE ON DATABASE datawarehouse TO platform_rw`, added to
`sql/00_bootstrap.sql` so a rebuild does not reintroduce it. Verified by a full extract -> load
cycle: `LOADED and contains no failed jobs`, dims now stamped 2026-08-08, and
`raw_smartmoving_staging` exists.

### The reason nobody noticed: the pipe-swallows-exit-code bug, again

`run.py ... | tail -25` reported **exit 0 while dlt was raising `PipelineStepFailed`**. A pipeline
returns its LAST stage's status. This is the same defect found in the dbt SSH command the same day,
and **every existing n8n workflow that pipes `run.py` output has it**. Any workflow that pipes must
use `out=$(cmd 2>&1); rc=$?; echo "$out" | tail -N; exit $rc`.

> This is the failure mode worth internalising: the pipeline was broken for 17 days, the schedules
> were green, and the only visible symptom was data that quietly stopped moving.

### Verified sound

| Check | Result |
|---|---|
| RLS from the consumer's side | Connected **as `app_read`**: reads `serving` + `core`, **denied** on `raw_smartmoving`, `staging`, `marts`, and denied on write |
| RLS policies | `rls_entity` on all 8 `core` + `serving` tables, via `core.current_role_can_see(entity_id)` |
| Rule 8 (UTC) | No naked `timestamp` anywhere except two `*_local` columns, which is the convention's sanctioned form |
| Rule 5 (idempotent merges) | 0 duplicate business keys across `opportunities_enriched`, `leads`, `customers_service_window`, `dim_branches`, `dim_users` |
| Report landing tables | Real composite PKs `(source_instance_id, report_generated_at, row_key)` |
| Grain | `core.opportunities` 2,169/2,169 - `jobs` 835/835 - `charges` 1,579/1,579 |

### Known, accepted, not defects

- **dlt raw tables have a unique index on `_dlt_id` only**, not on the business key. Idempotency
  comes from dlt's merge logic rather than a database constraint. Zero duplicates observed, but
  there is no database-level guard if that logic ever regresses.
- **`entity_id` is absent from dlt CHILD tables.** dlt stamps only the root row; children carry
  `_dlt_root_id` and the staging models join back. Deliberate.
- **`raw_smartmoving.report_ingest_errors` has no `entity_id`.** It is an operational log of emails
  that could not be attributed to an instance - an `entity_id` there would be a guess.
- ~~**Money is `double precision` in raw/staging**, cast to `numeric` before `core`; do not SUM money
  in `staging`.~~ **FIXED 2026-08-13** (architecture audit). Money is still `double precision` in
  **raw** - correct under ELT, raw preserves the payload - but every monetary column is now cast to
  `numeric` at the **staging** boundary, which is what staging is for. The redundant casts in
  `core.opportunity_charges` / `core.opportunity_payments` were removed. Money is safe to aggregate
  from staging onward, so the rule nobody could enforce is now a property of the schema.
- **43,338 webhook events, all with `processed_at` null.** Not a backlog in the harmful sense: dbt
  reads `webhook_events` directly, so the free status feed works and contributes 35,442
  observations. `processed_at` is the *enrichment worker's* marker, and that worker has never run.

---

## The sweep was the bottleneck, not the quota - 2026-08-08

The single most consequential correction so far, and it came from the business side, not the code.

`GET /api/customers?IncludeOpportunityInfo=true` returns the opportunity **GUID and quote number**
for every row - 685/685 on `ld`, 514/514 on `local`. That makes the *sweep*, not the per-opportunity
detail call, the cheap way to build the crosswalk that lets report rows attach to opportunities.

It had never been used that way because the sweep and the detail call were welded together in
`--job enrich`: widening the window dragged one detail call per opportunity with it, so the window
stayed pinned at 37 days and the crosswalk starved. `--sweep-only` separates them.

**Measured, both instances, 730-day window:**

| | Before | After | Cost |
|---|---|---|---|
| Report resolution | 10.2% | **41.0%** | |
| Crosswalk entries | 1,199 | **13,157** | |
| `core.opportunities` | 2,169 | **14,014** | |
| …with a customer | 708 | **13,157** | |
| …with money | 691 | **2,679** | |
| Webhook-only shells | 1,461 | **857** | |
| `core.leads` | 48 | **2,708** | |
| **Total API calls** | | | **81** |

A previously-proposed backfill of 1,461 targeted detail calls was **cancelled** - the sweep does
more, for ~5% of the cost.

**The structural limit this exposed, now recorded in the contract:** the sweep is *job-anchored*.
All 14,572 opportunities it returned have at least one job; none had zero. An opportunity that never
got a job scheduled is unreachable by the sweep at any window width - bad leads resolve at only
**5.6%** for exactly this reason. That population is what the reports exist to cover, which is the
strongest argument for treating reports as the backbone rather than a supplement.

> **Open, deliberately not papered over:** 2,458 report rows remain unmatched with no clean
> explanation - service dates inside the swept span, non-lead statuses. Job-anchoring explains bad
> leads and some lost opportunities, not all of it. One focused investigation is owed. Nothing is
> blocked: those rows surface in `marts.mart_unmatched_report_rows`.

---

## Architecture audit - 2026-08-13

A full read of the repository against the Phase 1 objective: one reliable source other teams consume
without calling a vendor API, as fresh as each source allows, replacing the Google Sheets.

**Verdict: no structural change is warranted.** The layering, the observation layer, the per-field
resolution, the instance/entity split and the contract-with-a-checker pattern are the right shapes for
this problem and should not be redesigned. What the audit found was documentation drift and one real
typing weakness - fixed below - plus a short list of things that are missing rather than wrong.

### Fixed in this pass

| Finding | What was wrong | Fix |
|---|---|---|
| **Money typing** | Money reached `staging` as `double precision`; the `numeric` cast happened in `core`. Correct results today, but it made "do not SUM money in staging" a rule people had to remember rather than a property of the schema. | Cast moved to the staging boundary in all four models that carry money; redundant `core` casts removed; the rule is now written in `CLAUDE.md` under **Conventions -> Money**. |
| **Stale freshness targets** | `serving_catalog.md` promised both published views a target several times tighter than the one the contract actually sets for jobs and leads (section 8 has the numbers; they are not repeated here). The catalog is what a consuming team would cite as our SLA, so it was publishing a commitment the pipeline does not meet. | Catalog now names the entity and links to `crm_sync_contract.md` section 8 instead of restating a number. |
| **The checker could not see that class of drift** | `check_sync_contract.py` guarded sweep windows and quota estimates, but not freshness targets - which is why the drift above survived. | Three freshness patterns added to `SINGLE_SOURCE_FACTS`. Verified the guard fires on a planted violation, not just that it passes. |
| **Rule 6 contradicted `decisions/0003`** | `CLAUDE.md` rule 6 said "no consumer reads `core`"; ADR 0003 deliberately relaxes exactly that, and the implementation follows the ADR. A non-negotiable rule was being negotiated elsewhere. | Rule 6 now states the bounded exception and links to the ADR. |
| **`raw_*` looked single-loader** | The layer table implied dlt loads all of raw. n8n writes `webhook_events` and every `report_*` table directly, by design. | Documented in the layer table - both loaders, and why each is right for its path. |
| **`intermediate/` was invisible** | The dbt folder is `models/intermediate/` but the schema is `marts`. Nothing said so, so the observation layer was hard to locate in Postgres. | Noted in the layer table. |
| **Stale `status` column note** | The catalog still described status labels as `status_<int>` placeholders "pending a full enum mapping". That mapping shipped with `dim_opportunity_status`. | Catalog now lists the real labels, warns that `status_<int>` would be a bug, and points at `status_model.md` for the Completed/Closed trap. |

### Open, unchanged by this pass

- **`marts.mart_enrichment_candidates` (P6) does not exist.** `pipeline/README.md` and `source.py`
  both describe it as the third change detector and "the real fix" for the sweep's blindness to money
  and `leadStatus`. Until it lands, an opportunity that changes money outside the enrichment allowlist
  and outside the hot window waits on the **cold TTL** to be re-read. That is a deliberate,
  documented backstop - but it is the largest remaining freshness gap in the system.
- **The exit-code sweep is not finished.** The 2026-08-08 audit established that *every* n8n workflow
  piping `run.py` hides failures. The migration doc carries the correct shape; the sweep itself is
  step 1 of Next Immediate Step and is what turns a 17-day silent outage into a visible one.
- **Three seeds have no consumer.** `dim_lob_map`, `dim_sales_team` and `dim_referral_source` load and
  are documented, but no model under `dbt/models/` references any of them. They are Phase 2 material
  (LOB and marketing reporting), not an oversight - recorded here so the next audit does not
  re-discover it as a gap.
- **`raw_*` has no database-level uniqueness on the business key**, only on `_dlt_id`. Idempotency
  rests entirely on dlt's merge logic. Zero duplicates observed across every table checked, but rule 5
  ("composite primary keys, idempotent loads") is currently enforced by application behaviour rather
  than by a constraint. Adding `UNIQUE (source_instance_id, id)` on the dlt root tables would make it
  structural. Cheap; not yet done.

---

## Next Immediate Step

**Migrate the n8n workflows.** Extraction is healthy again and the model is corrected, but nothing is
running on a schedule: the 6 workflows are drafts, still pointing at the old host path, and still
using the command shape that hides failures. Until they run, every number above is a snapshot that
will go stale exactly as it did on 2026-07-22.

Follow [deploy/n8n_workflow_migration.md](deploy/n8n_workflow_migration.md).

Then, in order:

1. **Migrate the 6 draft n8n workflows** to the new host path and the exit-code-safe command shape -
   see [deploy/n8n_workflow_migration.md](deploy/n8n_workflow_migration.md). Then publish them.
2. **Schedule the reports in the SmartMoving UI** (H2). Lead Status first: it is the denominator.
   Both per-instance aliases are live as of 2026-08-08.
3. **Remove the temporary `reporting@ecomoversmoving.com` alias** from `Resolve Report Metadata`
   once a report has arrived on each per-instance alias, and clear the one stale row in
   `report_ingest_errors` before that table is wired to an alert.
4. **The other three report staging models** + the Playwright bot for All Jobs.

### Report arm wired into core - DONE 2026-08-08

`report_lead_status` is now a real source, priority 5. On the droplet, **`PASS=204 WARN=0 ERROR=0`**.

| | |
|---|---|
| Observations contributed | 489 |
| Opportunities where the report is the freshest source | **472** |
| Opportunities that gained a money value they did not have | **657 -> 691** (total `2,313,887.88` -> `2,387,834.19`) |
| `pipeline_status` | now carries the lost/cancelled **subcategory** (`Lost price too high`, `Cancelled price was to high`) that the platform int cannot express |
| Grain | 2,169 / 2,169 - unchanged |
| `serving.jobs_upcoming_v1` | unchanged |

**Resolution rate is 10.2% (489 of 4,801), and that is expected.** The Lead Status export spans
three months of received dates; the API sweep is keyed on **service** date and only reaches
opportunities that have a job at all, so
most report rows describe opportunities the API has never been asked about. That history at zero
quota is the point. The unmatched rows are surfaced in `marts.mart_unmatched_report_rows` with a
reason, never dropped. The number to watch is `no_quote_number` (currently 0) - a rise there means
the export shape changed.

> **A correction to how this layer was documented.** `int_opportunity_observations` said adding a
> source was "a `union all` arm and nothing else". That is false: `core.opportunities` resolves
> each field against an explicit list of source branches, so an arm added without a matching
> `pick_latest` branch builds green, passes every test, and contributes **nothing**. That is
> exactly what happened on the first attempt - the arm landed 489 observations and `core` did not
> change by a single value. Both files now say so.

### Two empirical findings that shaped the arm

- **The report's `Status` cannot be mapped to the platform int.** On matched rows, 185 read
  `Closed` while the API says `status_code = 4` (Booked), and `Cancelled service no longer needed`
  maps to **both** 4 and 20. The arm therefore contributes the string to `pipeline_status` and
  leaves `status_code` null - the API owns the int.
- **`Estimated Revenue` -> `estimated_final_total`, on the strength of the column's name alone.**
  Every opportunity in the warehouse has `estimated_tax = 0`, so subtotal and final total are
  identical and the data cannot distinguish them. Re-check when a taxed opportunity first appears:
  if the mapping is wrong, it is wrong by exactly the tax on every report-sourced figure.

> Local read access when needed: SSH tunnel in **Windows PowerShell** (not WSL),
> `ssh -L 5433:localhost:5432 <droplet_ssh_user>@<droplet_ssh_host>` (values in laptop `.env`);
> the laptop connects to `127.0.0.1:5433`. Port 5432 is not exposed publicly, by design.

### dbt on the droplet - DONE 2026-08-07

`deploy/sync_droplet.py` created and run. **`PASS=198 WARN=0 ERROR=0 SKIP=0` on the droplet**,
identical to local. Verified by querying the droplet directly:

| | |
|---|---|
| dbt objects | **38** (6 `core` tables, 7 `marts`, 2 `serving`, 16 staging views, 7 seeds) |
| `core` row counts | opportunities 2,093 - jobs 835 - charges 1,579 - payments 41 - branches 8 - leads 48 |
| Report staging | 4,801 rows, **4,801 with quote / status / received_at / revenue** - no parse gaps |
| Timezone | `crm_timezone` resolves to `America/Los_Angeles`; `8/7/2026 7:16 AM` wall clock stores as `14:16Z` and renders back to `07:16` Pacific |
| RLS | enabled on all 8 `core` + `serving` tables; `core.entity_access` correctly exempt |
| `app_read` | `raw_smartmoving` USAGE = **false**, `core` + `serving` = true |

Deployment lives at **`/home/datawarehouse_user/datawarehouse`**, not `/opt/datawarehouse` as every
earlier draft of the docs said: `/opt` on this droplet is mode 700 owned by another application's
service user, and claiming space there would mean loosening permissions on a directory that is not
ours. `sql/00_bootstrap.sql` is excluded from the routine sync - it needs a superuser and ran once
at provisioning.

---

## Known Bugs - FIXED 2026-08-05 (Phase 1)

| # | File | Defect | Fix |
|---|---|---|---|
| 1 | `pipeline/sm_pipeline/source.py` | Change-hash covered only `(status, serviceDate, job ids/dates)` - all sweep-visible. A re-quote, charge edit, payment, or `leadStatus` CMET->**Booked** never triggered re-enrichment. | Hash widened to everything the sweep returns, **plus** a tiered staleness TTL. The structural blind spot is closed by the Phase 6 report queue. |
| 2 | `source.py` | `seen_ids` was `setdefault`-ed and appended every run, never reset. After run 2, `prior - seen` was permanently empty -> **soft-delete detection silently dead**; state grew unboundedly. | Presence now tracked as a per-record `seen` timestamp; state pruned at 120 days. |
| 3 | `source.py` | The sliding window caused **false deletions** - anything aging past the window start looked "disappeared", and two schedules using *different* windows thrashed each other. Every schedule now shares one window. | Deletion is gated on the record's service span overlapping the window of the sweep being evaluated. |
| 4 | `source.py` | `BudgetExceeded` mid-sweep soft-deleted every unseen opportunity. The hash was banked *before* `enrich_one` succeeded, so a failed detail call was never retried. | Only a sweep that paginates to completion is recorded as complete; watermarks are written only after a successful call. |
| 5 | `pipeline/sm_pipeline/client.py` | `get()` raised on any 4xx. An `opportunity-deleted` webhook -> `--ids <deleted>` -> 404 -> whole run died, taking every other batched id with it. | `get(..., allow_missing=True)` returns `None` on 404; the caller records a `detail_404` marker. |
| 6 | `source.py` | **Found during testing.** The original design assumed "dlt extracts resources in yield order, so `seen_ids` is fully populated when the deletions resource runs". **This is false** - dlt interleaves resources round-robin; a resource yielded last routinely runs before the sweep beside it has finished. Any within-run presence diff was a coin flip. | Deletion is evaluated against the last sweep *recorded complete in state*, making it independent of extraction order. |

**Bug 1 could not be fixed with a better hash.** The sweep returns only `{id, quoteNumber, status}` plus
`{job id, jobNumber, serviceDate, type}` - no widening surfaces money or `leadStatus`. The tiered TTL
bounds the blindness; the report-driven fingerprint queue (Phase 6) closes it properly.

**Two behaviours worth knowing:**
- **Deletion detection can lag by one run** when the deletions resource happens to be scheduled before
  the sweep completes. This is by design and safe - the `opportunity-deleted` webhook drives the
  immediate `detail_404` path, and sweep-disappearance is only a backstop.
- **A reappearing opportunity is force-re-enriched**, even if its hash and TTL say otherwise. Downstream
  decides "present again" by comparing `_sm_snapshot_at` to `_deleted_at`, so clearing the marker without
  a fresh snapshot would leave it looking deleted until its TTL happened to expire.

---

## Timezone Semantics - the report `*at Utc` columns are NOT UTC

**The vendor's column names lie.** Every report column suffixed `at Utc` renders in **the timezone the
CRM instance is configured with** - Pacific for this company today. The *API*'s `createdAtUtc` is
genuinely UTC. Same-looking name, two different meanings, and they will be silently unioned in the
observation layer if nobody stops it.

This must generalize: future companies will run CRM instances in other timezones.

1. **CRM timezone is an instance-level property, distinct from `core.branches.timezone`.** A branch's
   timezone is where it physically operates; the CRM timezone is how that instance's UI and exports
   render every timestamp. They can differ, and branches within one instance can span zones. Add
   `crm_timezone` (IANA) to the `dim_instance` seed and to `pipeline/sm_pipeline/instances.py`.
   **Never hardcode Pacific** - resolve per `source_instance_id` on every report cast.
2. **Timestamp columns** (`Start Time Utc`, `End Time Utc`, `Completed at Utc`, `Closed at Utc`,
   `Date Received`) - parse in the instance's `crm_timezone`, store as true `timestamptz` in UTC per
   CLAUDE.md rule 8.
3. **Date-only columns** (`Created at Utc`, `Booked at Utc`, `Job Date`, `Lost Date`, `Move Date`) are
   already **local business dates** - never timezone-convert them. Suffix them `_local`
   (`booked_date_local`). Do not name a column `booked_at_utc`: it is neither UTC nor a timestamp.
4. **Observation-layer hazard:** report `Created at Utc` (CRM-local date) and API `created_at_utc` (true
   UTC timestamp) are *different facts*. Never place them in the same `pick_latest` branch list.
5. Cross-source validation must be **timezone-aware**. An off-by-one here shifts every daily booked
   metric by a day.

---

## Enrichment Field Inventory - what each source contributes

| Field group | Source | Cost |
|---|---|---|
| Lead name, email, phone, origin + destination street/city/state/zip, referral, sales person, branch, move size, status, lost/bad reason, created | `GET /api/leads` list row | ~1-2 calls/day/instance. **Already landing.** |
| Opportunity `leadStatus` (business pipeline status), `estimatedTotal` (subtotal/tax/final), customer contacts, branch, tariff, move size, volume, weight, referral, estimator, sales assignee | `GET /api/opportunities/{id}` + all 10 `Include*` flags | 1 call/changed opportunity. Flags are **free**. **Already landing.** |
| Charge lines (estimated + actual), payments, surveys, job addresses (flat strings), crew | Same call, child tables | Free with the above. **Already landing.** |
| **Every lead and opportunity received in a period WITH its outcome** - authoritative `Status` incl. lost/cancelled reason, received-at, quote-sent, time-to-contact, estimated revenue, referral source. **The denominator for any conversion rate.** | **`lead-status.xlsx` scheduled report** | **Zero quota. The most important report in the set.** |
| **Structured** origin/destination (unit, street, city, state, zip, type - 14 cols), full estimated + actual financial breakdown (~42 cols), lifecycle timestamps, crew names, mileage, `move_date_is_tbd` | `all-jobs.xlsx` scheduled report | **Zero quota.** |
| `invoiced_amount`, `move_coordinator`, `booked_date` | `booked-opportunities-by-date-booked.xlsx` | **Zero quota.** |
| `lost_date`, `est_dollar_amount`, `time_to_first_contact` | `lost-leads-opportunities-details.xlsx` | **Zero quota.** |
| Live opportunity status between runs | Webhook status ledger (Tier 0) | **Zero quota.** Already live. |

**Not obtainable, and why:** lat/lng, stairs, elevator, parking, materials, and job notes exist only via
`GET /api/premium/opportunities/{id}/jobs/{jobId}` - **1 call per job**, the most expensive endpoint in
the API. Deliberately skipped; the reports give structured addresses without it.

---

## The Plan - dependency-ordered

```
P0  probes + deploy dbt + on-run-end RLS        <- blocks everything
 |- P1  source.py bug fixes                      (parallel)
 \- P2  seeds + core.branches + crm_timezone
     \- P3  enriched staging + quote crosswalk
         \- P4  observation layer + core rewrite
             |- P5  reports (needs H1, H2)
             |   \- P6  enrichment candidates queue
             \- P7  serving
                 \- P8  schedules + catalog
```

- **P1 - Fix `source.py`.** Replace `opp_hashes`/`seen_ids`/`prior_ids` with one `st["opps"]` map holding
  hash, last-enrichment time, service date, `leadStatus`, and a soft-delete marker. `seen` becomes a
  run-scoped set, never state. Widen the hash to *everything the sweep returns*. Add a tiered staleness
  TTL (24 h for `[today-3, today+21]`, 14 d elsewhere - a flat 24 h across the whole window would be
  calls/month). Gate deletions on the service date being inside *this* sweep's window; add a `sweep_ok`
  flag; move hash writes to after a successful call; add `allow_missing=True` for 404s.
- **P2 - Seeds and timezone authority.** Load the five `OLD_TABLES/SCRDLA - *.csv` files as dbt seeds
  (strip the Spanish notes row 2 from two of them - it would load as data). Add `crm_timezone` to
  `dim_instance`. Build `core.branches` - the timezone authority CLAUDE.md mandates. Replace the three
  hardcoded `'America/Los_Angeles'` literals. **Move RLS into an `on-run-end` hook**: at 5 builds/day,
  "run `sql/10_apply_rls.sql` manually" is not viable, and between the `drop table` and the manual `psql`
  **`app_read` sees every entity's rows**.
- **P3 - Staging for the enriched data.** One model per raw table; charges as a single model with an
  `estimated`/`actual` discriminator. Plus `int_opportunity_quote_crosswalk` - `(instance, quote_number)
  -> external_opportunity_id`, the bridge every report needs.
- **P4 - Observation layer, API arms only.** Build it before reports so Phase 5 adds `union all` arms
  with **zero rework of core**.
- **P5 - Reports.** n8n IMAP flow -> `report_*` landing -> staging -> new observation arms.
  **Lead Status is the priority report**, and its landing table (`sql/33`), source declaration, cast
  macros and staging model are already built ahead of schedule - only the n8n IMAP flow is missing.
- **P6 - Report-driven enrichment queue.** The real fix for bug 1.
- **P7 - Serving.** Additive columns on both existing views; two new views.
- **P8 - Schedules.** Align n8n with [`crm_sync_contract.md`](crm_sync_contract.md) section 6.

### Design correction to sync strategy 12.3 - BUILT AND PROVEN (2026-08-05)

The sketched row-level `select distinct on (...) order by observed_at desc` is **wrong for this source
mix and was not built.** It returns one whole row from one source, but the sources are
*complementary*: the reports know `invoiced_amount`, `move_coordinator`, `booked_date` and structured
addresses; the API knows `leadStatus`, `estimated_total__*` and charge lines. A row-level winner nulls
out everything the winner does not know.

**Measured, not argued: 177 of 657 opportunities (27%) have a sweep observation MORE RECENT than their
enrichment.** The sweep carries no money. Row-level resolution would have silently wiped
`estimated_final_total` on all 177. Per-field resolution keeps all 177 - verified zero wiped, total
reconciles to the cent.

Implemented as the `pick_latest` macro. The null-skip also defuses a second trap: the sweep re-stamps
its extraction timestamp 5x/day even when nothing changed, so it would always out-timestamp an older
enrichment. Correct for fields it knows, harmless elsewhere because it contributes NULL there.

Recorded as [decisions/0005](decisions/0005-latest-observation-wins-is-per-field.md).

---

## Open Questions

### Probes

| | Probe | Result |
|---|---|---|
| P1 | Does `_dlt_list_idx` exist on the charge/address child tables? | **ANSWERED - yes**, on every child table, and unique per parent (1458/1458, 1469/1469). Used as `charge_seq` / `address_seq`. |
| P2 | `quote_number` type on both sides | **ANSWERED - they differ.** `bigint` on `opportunities_enriched`, `character varying` on the sweep child. Normalised to text in staging; without that cast the crosswalk silently returns nothing. |
| P3 | Does the report's `Job Id` GUID equal `external_job_id`? | **Still open** - needs a real report file. Note `opportunities_enriched__jobs.id` and the sweep's job ids overlap 765/765, so the internal job identity is consistent. |
| P4 | True opportunity count in a full sweep | **Partially answered** from the dev warehouse: 708 opportunities in the sweep, 657 enriched (51 not yet). Re-measure on the droplet after the P1 pipeline fixes run. |

### The status model (read [status_model.md](status_model.md) before counting anything)

Settled 2026-08-05. There are three status fields and only one is authoritative.

- **`status` (integer) is THE field every metric counts on.** Nine values:
  `0 NewLead, 1 LeadInProgress, 3 Opportunity, 4 Booked, 10 Completed, 11 Closed, 20 Cancelled,
  30 Lost, 50 BadLead`. Now in the seed **`dim_opportunity_status`** with labels and boolean flags.
  Leads and opportunities share this enum, so "booked" means one thing everywhere.
  Two rules that are easy to get wrong: **Completed and Closed both count as booked** (they passed
  through booking), and **BadLead is the only status excluded from a conversion denominator**.
- **`leadStatus` (string) is a CRM pipeline label - context, never a metric.** Modeled as
  `pipeline_status`. It does not track the outcome: a `status=30` (Lost) opportunity can read
  `'Booked'` here.
- **The report `Status` string is authoritative AND carries the reason** (`Lost price too high`).
  Maps through `dim_status_map` at 99% coverage to the same `status_category` vocabulary, so counts
  agree from either side.

**Delivered:** `dim_opportunity_status` seed; `core.jobs` and `core.leads` now expose
`*_status_label`, `*_status_category` and real boolean `is_booked / is_lost / is_cancelled /
is_completed / is_bad_lead / is_open`; hardcoded `case` label logic removed. Conversion rate is now a
one-liner. Flags load as booleans (not 0/1) so `where is_booked` works without `= 1`.

> **Contract note - `serving.jobs_upcoming_v1.status` values changed.** Same 15 columns, same type,
> but placeholders became real names: `status_20` -> `Cancelled`, `status_30` -> `Lost`,
> `status_3` -> `Opportunity`. This is a fix, not a feature, and it is safe now because no consumer
> app exists yet (roadmap Phase 3 has not started). Had one existed this would have needed a v2.

### Findings that CORRECT the existing docs

- **The two endpoints do NOT use different status codings.** `smartmoving_api_findings.md` and
  `smartmoving_sync_strategy.md` both warn that the sweep and the detail endpoint code `status`
  differently and that "only 4=Booked is stable". Measured across all 657 enriched opportunities the
  two agree **100%** (4=4, 30=30, 20=20, 3=3, 10=10, 50=50, 11=11). No defensive reconciliation needed.
  The genuinely separate namespace is `status` int vs `leadStatus` string - a `status=30` row can carry
  `leadStatus='Booked'`.
- **`lead_status` is dirty in a way that silently breaks counting.** Both `'Booked'` (283) and
  `'Booked '` (51) occur in the same column. Untrimmed they group as two statuses and booked counts run
  **15% low**. Trimmed once at the staging boundary.
- **`__contacts` and `__opportunity_documents` DO exist** (18 and 455 rows) - earlier notes said they
  did not. The enriched parent has 48 columns, not 44; `move_coordinator__*`, `cancellation_reason`,
  `affiliate_*` and `trip_info__is_trip_info_applied` are all present.
- **Job addresses are not an origin/destination pair.** Measured: 84 jobs have 1 address, 645 have 2,
  29 have 3, 2 have 4. "Last one is the destination" is wrong for 115 jobs. Confirms that structured
  addresses must come from the report.

### Human decisions

- ~~H1 - How does n8n learn `source_instance_id` from an email?~~ **RESOLVED 2026-08-06.** Two
  dedicated aliases, mapped exactly (no fuzzy matching) in the `report_ingest` workflow:
  `ld.reporting@ecomoversmoving.com` -> `ld`, `local.reporting@ecomoversmoving.com` -> `local`.
  An email whose recipient matches neither lands in `report_ingest_errors`; it is never guessed.
  > **TEMPORARY TEST ALIAS - REMOVE BEFORE GO-LIVE.** `reporting@ecomoversmoving.com` (generic, no
  > instance in the name) is currently mapped to `local` purely to validate the flow end to end.
  > A generic mailbox cannot identify an instance, so any later report sent there would be silently
  > attributed to `local`. Delete that entry from the `Resolve Report Metadata` node once the two
  > per-instance aliases are configured in the SmartMoving UI.
- **H2 - Report schedules in the SmartMoving UI.** Recommend, per instance, daily:
  **Lead Status 05:55 (schedule this one FIRST - it is the denominator)**, All Jobs 06:00,
  Booked-by-Date-Booked 06:05, Lost Leads 06:10, all *This Month*. Plus a one-time **All Time** export
  of **Lead Status** and All Jobs per instance for zero-quota historical backfill. Schedule only the
  `by-date-booked` booked variant - the `by-service-date` variant is schema-identical and would
  collide on the primary key.
- **H3 - RESOLVED.** The report `*at Utc` columns are CRM-configured-timezone, not UTC. See
  "Timezone Semantics" above.
- ~~H4 - `dim_status_map` keying~~ **RESOLVED 2026-08-05.** The seed keys on the **scheduled-report
  `Status` string** (enum name + lost/cancelled subcategory), not on `leadStatus`. Measured coverage
  against the Lead Status export: **99% of 5,278 rows**. No two-step lookup needed - a single
  `norm_text` join on both sides is sufficient. The one gap, `Cancelled no availability` (5 rows), was
  added to both the seed and the source sheet.
- ~~H7 - `dim_status_map` covers only 2 of 8 statuses~~ **WITHDRAWN - I had this wrong.** I was
  matching the seed against `leadStatus`, which is not what it maps. `leadStatus` is a CRM pipeline
  label (context only, never a metric); the authoritative field is the `status` **integer**. See
  [status_model.md](status_model.md).
- ~~H6 - `dim_referral_source` duplicate `Affiliate - Adrian`~~ **RESOLVED 2026-08-05.** The near-empty
  stub was a strict subset of the populated row; removed from both the seed and the source sheet.
  Confirmed correct by the user. 10 fully-blank rows also dropped on load.
- **H8 - `charge_category` needs a verified mapping.** Charge lines carry an int enum (observed
  1,2,3,4,7,9,10; names suggest labour / transportation / materials / warehouse / valuation / storage /
  shuttle). Deliberately left unlabelled - inventing names for unverified codes is how wrong business
  logic gets baked in. Needs a seed read off the SmartMoving UI before any charge-category reporting.
- **H5 - Retire the legacy `local` API consumer** (45% of that instance's quota). Not urgent at current
  volumes, but it is what buys real headroom.

### Workbook facts that shape the parser
- `all-jobs.xlsx` has **no `Quote #`** - but `Job Number` is `<quote>-<seq>` (`131118-2`), giving a second,
  independent path to the opportunity. Free crosswalk validation.
- All report dates are `M/D/YYYY` **strings**, not Excel serials -> `to_date(x,'MM/DD/YYYY')`, never a
  bare `::date` (that depends on `DateStyle`).
- **Empty cells are physically omitted from the XLSX row XML.** The parser must materialise every declared
  header as `null`, or `row_data` shape varies row-to-row and schema-drift detection breaks.
- Sheet names differ (`jobs` for all-jobs, `data` for the rest) -> read sheet **index 0**, never a name.
- Report `Status` / `Opportunity Status` are the **pipeline string**, the same namespace as `leadStatus` -
  never merge them with the platform int.
- `report_generated_at` must come from the email's RFC-2822 `Date:` header (fallback IMAP INTERNALDATE),
  **never `now()`** - ingest delay would make a stale report falsely out-rank fresher API data.

---

## Target Schedule and Quota

**Moved to [`crm_sync_contract.md`](crm_sync_contract.md) sections 5-7.**

The schedule, the quota model and the enrichment-trigger allowlist now live in exactly
one file. They used to be restated here, in `smartmoving_sync_strategy.md`,
`pipeline/README.md` and `serving_catalog.md`, and the four copies disagreed about both
cadence and cost. `scripts/check_sync_contract.py` fails the build if they reappear.

Still true and specific to this status document: the webhook enrichment worker is the
only line item that can run away, so it keeps a per-run `--budget` **and** a daily
ledger gate reading `scripts/api_call_log.jsonl`. Cheap sweeps and leads polls are
never paused.

## Completed

### Repository (2026-08-05)
- [x] Pushed to `https://github.com/NicolasCortesEcoM/Eco-Movers-Datawarehouse`.
- [x] `.gitignore` excludes `smartmoving_scheduble_reports/` (live customer PII), `scripts/api_call_log.jsonl`,
      `.playwright-mcp/`, `dbt/target/`, `dbt/logs/`, `dbt/.user.yml`, `**/__pycache__/`. Files left on disk, not deleted.
- [x] All droplet/SSH/webhook values replaced with placeholders in docs; real values only in `.env`
      (`droplet_ssh_host`, `droplet_ssh_user`, `n8n_docker_gateway`, `smartmoving_webhook_url`, `reporting_webhook_url`).

### RAW Layer + Enrichment (validated end-to-end)
- [x] dlt extraction: `leads`, `customers_service_window` (thin sweep), 11 dimensions - `pipeline/sm_pipeline/source.py`
- [x] **Diff-driven enrichment** `--job enrich`: customers sweep as change detector -> only changed
      opportunities call `GET /api/opportunities/{id}` with all 10 `Include*` flags. Output:
      `raw_smartmoving.opportunities_enriched` plus child tables.
- [x] dlt-state watermark persists in the destination; unchanged reruns cost only the sweep, 0 enrichment calls.
- [x] Targeted enrichment `--ids a,b,c` (no sweep), the webhook worker entrypoint.
- [x] Soft-delete for disappeared opportunities -> `raw_smartmoving.opportunity_deletions` (**see bug 2** - currently inert).
- [x] 429 rate-limit handling with `Retry-After` retry plus proactive `pace` around 1.6 calls/sec.
- [x] Seed: **178 ld opps + 479 local opps**, all with estimates; 1,458 charges, 1,469 addresses, 41 payments.
- [x] Idempotency verified: ld rerun = 2 calls (sweep only), 0 duplicates.

### Landing Tables
- [x] `sql/20_webhook_events.sql` - append-only webhook log + deadletter, dedupe by hash.
- [x] `sql/30_report_landing.sql` - `report_all_jobs`, precedence by `report_generated_at`, JSONB fidelity.
- [x] `sql/31_report_booked_lost.sql` - `report_booked_opportunities` + `report_lost_leads`, same contract.

### Transformations + Contracts
- [x] dbt: staging -> core (`jobs`, `leads`) -> serving. 34/34 tests green.
- [x] `serving.jobs_upcoming_v1` and `serving.leads_today_v1` published and cataloged.
- [x] RLS by `entity_id` (`sql/10_apply_rls.sql`), cross-entity isolation verified.

### Droplet - Migrated And Live (2026-07-22)
- [x] `datawarehouse` database created; `sql/00_bootstrap.sql` applied.
- [x] `platform_rw` and `app_read` created; both connect successfully.
- [x] Laptop -> droplet SSH tunnel verified in Windows PowerShell.
- [x] **Local -> droplet migration via Python/psycopg2** (`pg_dump` unavailable): 34 `raw_smartmoving`
      tables, **18,637 rows**, API quota = 0. dlt state preserved. Droplet runs **PG 14**, so
      `NULLS DISTINCT` was removed from reflected DDL.
- [x] `dbt build` on the droplet: **34/34 green**; `serving.jobs_upcoming_v1` = 641 rows.
- [x] `sql/10_apply_rls.sql` on the droplet, made resilient to redundant non-owner GRANTs.
- [ ] Point `.env` (`postgres_*`) at the droplet through the tunnel for the next pipeline runs.
- [ ] **Daily `pg_dump`/backup to Spaces/S3.** Early priority - if the droplet dies without a backup, the warehouse is lost.

### n8n Webhook Log - Live (2026-07-22)
- [x] `Datawarehouse Postgres` credential (host `<n8n_docker_gateway>`, value in laptop `.env`).
- [x] Workflow `Reporting_datawarehouse` (id `KswuBX6pyuAAziEj`). The old `Cancelled Opportunity`
      workflow (`fSs1rIV9Ik0m0824`) remains untouched and separate.
- [x] Both instances send 17 events with `x-sm-instance: ld|local` plus shared `x-sm-secret`.
- [x] Verified with real traffic: 160 events captured, both instances. API cost = 0.

### Enrichment Orchestration - Built As Drafts (2026-07-22)
- [x] **Tier 0 - status ledger without API calls.** `stg_smartmoving__webhook_opportunity_status` +
      `int_opportunity_status_latest`. **136 live opps by status, API cost = 0.** 8 tests OK.
- [x] **Worker `Enrichment_worker`** (id `XPBsZoF7goshMuz8`) every 5 min: unprocessed high-value events ->
      debounce to distinct `--ids` by instance -> SSH `run.py --ids ... --budget 200` -> mark processed or
      deadletter after 5 attempts. A parallel branch drains low-value events without spending quota.
- [x] **Schedules:** `leads_poll` (id `lA0spX6AFyc3iNAg`), `opps_sweep` (id `eFQUiMawRkEMJoyX`),
      `weekly_dims` (id `p6fjQ24sIBHRSWfM`), `nightly_reconciliation` (id `Sve0TiQArFuEcAXX`).
- [ ] Deploy the pipeline on the host, confirm the SSH credential, publish the 6 workflows.

### Pending - the current workstream
- [ ] **P0** Deploy dbt to the droplet; run the four probes; `on-run-end` RLS hook.
- [x] **P1** Fix the six `source.py` / `client.py` bugs (2026-08-05). New CLI flags
      `--hot-ttl-hours` (24), `--cold-ttl-hours` (336), `--refresh-stale-hours`. State migrates itself
      from the legacy `{opp_hashes, seen_ids, prior_ids}` layout on first run. Verified against a fake
      API through a real dlt pipeline: 15 scenarios green, covering rerun idempotency, narrow windows,
      mid-sweep failure, genuine disappearance, reappearance, 404 handling, legacy migration, TTL
      tiering, and state pruning. **Not yet run against the live API or the droplet.**
- [x] **P2** Seeds, `core.branches`, `crm_timezone`, hardcoded timezones removed (2026-08-05).
      6 seeds in `dbt/seeds/` (the five `OLD_TABLES/SCRDLA - *.csv` plus `branch_timezone`);
      Spanish column notes preserved as `_seeds.yml` descriptions instead of a phantom data row.
      New: `core.branches` (timezone authority, carries `timezone` + `crm_timezone` + the only free
      geocoded address in the API), `stg_smartmoving__branches`, macros `norm_text`, `entity_today`,
      `apply_rls`. RLS now runs as an `on-run-end` hook. **Verified against the local dev warehouse:
      78/78 tests green (was 34), `serving.jobs_upcoming_v1` contract byte-identical (same 15 columns),
      RLS re-enabled on all 5 core+serving tables with `entity_access` correctly excluded.**
      Generalization proven end-to-end by temporarily setting one branch to `Pacific/Auckland` and
      confirming derived local dates moved with it, then reverting.
- [x] **P3** Enriched staging + quote crosswalk (2026-08-05). 8 staging models + 2 intermediate;
      all 13 raw enriched tables accounted for (8 modeled, 4 rolled into attachment counts, 1 parent).
      **146/146 tests green** (was 78). Verified against the dev warehouse: **zero row loss** on every
      model, estimated charge total and opportunity total reconcile to the cent
      (2,317,448.20 / 2,313,887.88), crosswalk resolves 708 quotes with 0 unresolved and 0
      quote-to-two-opportunities violations, and both serving contracts are unchanged (15 / 24 cols).
      A column-by-column completeness audit flagged 12 apparent omissions; all 12 proved to be
      renames, and 5 apparent value differences were all `nullif(x,'')` collapsing empty strings.
- [x] **P4** Observation layer + `core.opportunities` + `core.jobs` rewrite (2026-08-05).
      **198/198 tests green** (was 156). New: `pick_latest` macro,
      `int_opportunity_observations` / `int_opportunity_latest_by_source`,
      `int_job_observations` / `int_job_latest_by_source`, `core.opportunities` (708 rows - 657
      enriched **plus 51 sweep-only that previously had no representation at all**),
      `core.opportunity_charges`, `core.opportunity_payments`. `core.jobs` rebuilt off the
      observation layer at the same 835-row grain; `int_opportunity_status_latest` is now a filter
      over the shared observation model instead of duplicating the webhook parsing.
      **Verified:** serving contracts structurally unchanged (15 / 24 cols); money reconciles to the
      cent (2,313,887.88 core vs staging); charges 1,579 and payments 41 preserved.
      **The design correction is empirically validated** - see the note below and
      [decisions/0005](decisions/0005-latest-observation-wins-is-per-field.md).
- [~] **P5** **n8n `report_ingest` workflow built (2026-08-06)** - id `3NRvDchKPT5RK4tn`, currently
      INACTIVE pending the IMAP credential. One IMAP route serves all four reports: resolve instance
      from the recipient alias -> resolve report type from the subject -> parse xlsx -> land `row_data`
      verbatim as jsonb with `ON CONFLICT DO NOTHING`. `sql/32_report_ingest_errors.sql` created and
      applied; `sql/31` also applied locally so dev matches the droplet.
      Two node options do real work: `includeEmptyCells` fills blank cells so `row_data` keeps a stable
      shape, and `readAsString` keeps every value as text, which is what the `rpt_*` cast macros expect.
      **Architecture rule: the All Jobs bot only makes the email arrive.** It never parses or loads -
      otherwise there would be two parsers and two landing contracts for the same report.
      **Alerting (2026-08-06):** `datawarehouse_error_handler` (id `J1y2uCUFvCcNkZjZ`, published) posts
      HARD failures to Slack `C075FDBFGHY` via `chat.postMessage`, mirroring the existing
      Daily-Meetings error handler. `report_ingest` points at it via `errorWorkflow`. Separately, an
      `Alert Unrecognised Report` node fires the moment an email cannot be resolved - those are
      *handled* outcomes, not crashes, so the error trigger would never see them. Two failure classes,
      two alerts, deliberately.
      > ~~The Slack credential guess was wrong~~ **RESOLVED 2026-08-07.** The guessed credential
      > (`Slack BOT n8n`) returned `channel_not_found` on `C075FDBFGHY` - that error means the TOKEN
      > cannot see the channel (wrong workspace/bot), not that the channel is missing. Switched to
      > **`EcoBot`**, which has access. Worth noting the general lesson: an alert path is not working
      > until a real message has arrived, because a silent alerting failure manufactures confidence.
      **Droplet (2026-08-06):** `report_ingest_errors` AND `report_lead_status` applied - the latter
      had only ever been applied locally, so the droplet was missing the table the whole flow targets.
      All five `report_*` tables now present.
      **First real email tested 2026-08-07 - two design assumptions were WRONG.** The mailbox now
      connects and the alias/instance/date resolution all work, but:
      1. **The report is NOT attached.** SmartMoving emails a **download link** to Azure Blob Storage
         (`.../report-exports/<guid>/lead-status.xlsx`); the message is plain `text/html` with no
         multipart body. The file must be fetched over HTTP before it can be parsed.
      2. **The subject is generic.** Every report arrives as *"Your SmartMoving Report is Ready!"*,
         so it identifies nothing. The report type must come from the **filename in the download URL**
         (`lead-status.xlsx`, `all-jobs.xlsx`, ...), which matches the sample exports exactly.
      The email body also states *"containing N records"* (4,801 in the test), which gives a free
      integrity check: compare rows landed against the count SmartMoving claims it sent, so a silent
      truncation becomes visible.
      The corrected `Resolve Report Metadata` node is applied and **verified against the real email**:
      resolves `lead_status`, `report_lead_status`, the download URL, and `expected_records = 4801`.
      Full node-by-node configuration is version-controlled at
      [deploy/n8n_report_ingest_setup.md](deploy/n8n_report_ingest_setup.md); the Code node itself at
      [deploy/n8n_report_ingest_resolve_node.js](deploy/n8n_report_ingest_resolve_node.js).
      **END-TO-END GREEN 2026-08-07.** `Download Report File` (HTTP -> binary `data`),
      the corrected `Extract Report Rows`, and the two row-count verification nodes were applied and
      the full flow ran on the real email. `Assert Row Count Matches` returned
      `expected_records: 4801, landed_records: 4801, verified: true`.
      **Post-run database audit - every check passed:**
      | Check | Result |
      |---|---|
      | Rows landed / distinct `row_key` | 4,801 / 4,801 - no duplicate Quote # |
      | Header count per row | **16 on every single row** - `includeEmptyCells` works; 4,796 rows carry at least one empty-string cell that xlsx would otherwise have omitted |
      | Headers vs `stg_smartmoving__report_lead_status` | all 16 consumed, none unmapped |
      | Fallback `__nokey__` hashes | **0** - `Quote #` populated on every row |
      | `report_generated_at` | `2026-08-07 14:22:10Z` from the `Date:` header, not `now()` |
      | **Instance attribution** | **PROVEN.** All 6 report branches (Seattle, South Sound, Kirkland, Lynnwood, Bremerton, Long Distance Team) match `local` exactly; **0 match `ld`** (Main Office, South Sound LD). The one silent failure mode in the whole design is ruled out for this email. |
      | `dim_status_map` coverage | **38/38 observed statuses mapped, 0 unmatched** |
      | Received-at span | 2026-05-09 -> 2026-08-07 (~3 months) |
      | Quote crosswalk | 455 of 479 `local` API opportunities found in the report; the other 24 fall outside the report's received-date span, as expected |
      > **One stale row in `report_ingest_errors`** - the pre-fix run of this same email
      > (`unrecognised report subject | email has no attachment`). It is a false positive: that
      > `message_id` ingested successfully afterwards. Clear it before the table is wired to an alert,
      > or the first real alert will be noise.
      Remaining: schedule the reports in the SmartMoving UI, the dbt cascade workflow, and the
      other three staging models.
- [~] **P5** **Lead Status report done ahead of schedule (2026-08-05):** `sql/33_report_lead_status.sql`
      landing table applied, source declared, `report_casts.sql` macros, and
      `stg_smartmoving__report_lead_status`. **Validated by loading the real 5,278-row export into the
      dev warehouse and running the actual parser**: every null has a documented cause (331 `0/0/0`
      service-date sentinels, 1,543 blank Quote Sent, 134 blank + 3 `--` time-to-contact), 0
      unexplained; status classified **5,278/5,278 with zero unmatched**; timezone conversion verified
      (`12:16 AM` Pacific -> `07:16` UTC). Test PII was truncated from the dev table afterwards.
      Remaining for P5: the n8n IMAP flow, the other three reports, and the observation arms.
- [ ] **P6** `mart_enrichment_candidates` + `enrichment_from_reports` workflow.
- [ ] **P7** Additive columns on both serving views; new `serving.opportunities_v1` and `serving.jobs_v1`.
- [ ] **P8** Align schedules with the sync contract; update `serving_catalog.md`.
- [ ] Complete the sweep `status` enum mapping (3/10/20/30/50).

### Deferred, deliberately
- [ ] Lead -> opportunity map. Sync strategy 10.1 proposes a fuzzy email/phone/branch/date match. Out of
      scope: leads and opportunities stay separate this phase.
- [ ] Notes, follow-ups, interaction history, inventory item lines, document URLs, Premium per-job calls.

---

## Connection Architecture (established 2026-07-22)

- **Droplet:** address in laptop `.env` as `droplet_ssh_host`, hostname `n8n`. **Postgres and n8n live on
  the same machine.** n8n reaches Postgres through `localhost` from the host side, with no tunnels and no
  public database port.
- **Dedicated database:** `datawarehouse`, separate from the overtime app DB. Isolation is at database
  level, not schema level. Schemas: `raw_smartmoving`, `staging`, `core`, `marts`, `serving`.
- **Roles:** never connect apps as `postgres` or superuser.
  - `platform_rw` - dlt + dbt. Owner of everything inside `datawarehouse`.
  - `app_read` - consumer apps. `SELECT` only on `serving` + `core`, with RLS by `entity_id`.
  - **Rule:** one role per access pattern, not per app. Entity isolation comes from RLS
    (`core.entity_access`). Create a new role only when permissions differ.
- **Laptop access:** SSH tunnel only; do not open port 5432.
  ```bash
  ssh -L 5433:localhost:5432 <droplet_ssh_user>@<droplet_ssh_host>
  # values in laptop .env: droplet_ssh_user, droplet_ssh_host
  # with the tunnel open, the laptop connects to localhost:5433 -> droplet Postgres
  ```
- **Backups:** pending, early priority. Self-hosted means backups are our responsibility.
- **n8n runs in Docker; Postgres runs natively on the host.** Docker `localhost` points to the container.
  - n8n network `n8n-docker-caddy_default`, gateway in laptop `.env` as `n8n_docker_gateway`.
  - `ufw allow from 172.18.0.0/16 to any port 5432 proto tcp`, plus one `pg_hba.conf` line per role. PG 14.
  - `ot-project-db-1` is the overtime project's Postgres 16 container, completely separate. Do not touch.

---

## Key Facts And Decisions

- **Quota:** 125k/month **per instance**. `local` was already around 45% from an existing app that should
  be retired; `ld` around 6%.
- **Short-window rate limit** around 120/min in addition to the monthly quota - see `smartmoving_api_findings.md`.
- **`Include*` flags cost no extra quota.** Always request all 10 on the opportunity detail call.
- **`GET /api/leads/{id}` is byte-identical to a list row.** Never call it.
- **No lead-created webhook:** leads are always polling. A converted lead disappears from `/api/leads` but
  continues as an opportunity through sweep + enrichment; raw keeps both halves.
- **`PageSize` caps at 200**; requesting more silently returns 200. Date filters are integer `YYYYMMDD`.
- **No `modifiedSince` filter exists anywhere** in the 65 endpoints. This is why the hash-diff sweep exists.
- **Self-hosted droplet persistence** is correct for Phase 1. Move to Managed Postgres only on the
  `CLAUDE.md` trigger: analytical queries compete with n8n, or history outgrows the operational DB.
- **Audit workflow `Cancelled Opportunity`** (`fSs1rIV9Ik0m0824`) stays active, untouched, and unrelated.
  It has API keys hardcoded in plaintext and should eventually use the `SM LD API` / `SM API LOCAL API`
  credentials; pending, not urgent.
