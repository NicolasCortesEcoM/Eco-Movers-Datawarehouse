# SmartMoving -> Postgres Synchronization Strategy (CDC / freshness)

**Prepared for:** Nicolas - Data Team
**Date:** July 2026, revised for a Postgres destination
**Scope:** SmartMoving only (Premium API + webhooks + Scheduled Reports). Out of scope: Playwright web scraping, QuickBooks, marketing, phone systems, and payroll.
**Reference stack:** dlt + PostgreSQL + dbt (`dbt-postgres`) + n8n, according to `CLAUDE.md`, which is the authoritative architecture source. The warehouse is **PostgreSQL only** for this project; there is no separate analytical warehouse in scope.

**Instance vs entity model:** a SmartMoving instance is **not** the same thing as a business entity. One group company has **two instances for one entity**, split by line of business: Long Distance and Local + Commercial. Other companies will usually have one instance. Therefore:

- The whole pipeline is parameterized by **`source_instance_id`**, the instance/API key that produced the data, and stamps it on each raw table with `entity_id`.
- A `dim_instance` seed maps `source_instance_id` -> `entity_id` plus `lob_hint`. For split line-of-business instances, the instance itself is the most reliable LOB signal and takes precedence over `dim_lob_map` rules.
- Each instance has its own 125,000 calls/month quota and its own budget/ledger. n8n schedules iterate over the instance list. Adding a company = one seed row + one API key.
- SmartMoving GUIDs are only unique within an instance. Every warehouse primary key is composite: (`source_instance_id`, `id`). The entity 360 joins both halves by `entity_id`.

---

## 1. Executive Summary

Three hard SmartMoving constraints define the design:

1. **No modified-date filter** in the API, so frequent full-history polling is not viable.
2. **125,000 calls/month quota**; every page and every error counts, so every call must be budgeted.
3. **Only 7 days of webhook history** in SmartMoving, so recovery from missed events must be owned by us and run within hours, not days.

The answer is a hybrid architecture with **three paths that have different roles and converge into the same raw tables with idempotent merges**:

| Path | Role | Freshness | Quota cost |
| --- | --- | --- | --- |
| **Webhooks + enrichment** | Primary for opportunities, jobs, follow-ups, payments, customers | Minutes | 1 call per useful event, debounced |
| **Date-window polling** | Primary for new leads; reconciliation for everything else | 15-60 min | ~250-400 calls/day |
| **Scheduled Reports by email** | Storage, historical backfill, audit | Daily | **Zero** |

Steady-state budget, the mechanism costs and the kill-switch thresholds live in [`crm_sync_contract.md`](crm_sync_contract.md) section 7 - the authority. Do not restate them here.

**Critical finding:** SmartMoving does **not** offer a lead-created webhook. The 17 available events start at `opportunity-created` (see `smartmoving_api_findings.md`). Therefore "leads received today" is handled by polling `GET /api/leads?From=today` every 15-30 min.

---

## 2. Synchronization Flow

```text
PATH 1 - REAL TIME (webhooks)
SmartMoving webhook -> n8n endpoint (host in laptop `.env` as `smartmoving_webhook_url` / `reporting_webhook_url`)
  -> validate secret header and respond 200 immediately
  -> INSERT into raw_smartmoving.webhook_events
     (append-only: received_at, event_type, resource_id, payload JSONB, dedupe hash)
  -> n8n schedule every 2-5 min reads unprocessed events
  -> debounce by resource id
  -> dlt enrichment: GET detail by id with all Include* flags
  -> raw_smartmoving opportunities/jobs/customers/payments/followups
  -> dbt: staging -> core -> marts -> serving

PATH 2 - POLLING (n8n schedules; primary for leads, reconciliation for the rest)
*/15-30 min: GET /api/leads?From=today&To=today&IncludeBad=true&IncludeLost=true
hourly: GET /api/customers?FromServiceDate=today&ToServiceDate=today+10&IncludeOpportunityInfo=true
nightly: expanded window [today-7, today+30] + leads [today-7, today]
weekly: dimensions such as branches, users, referral sources, service types, move sizes, tariffs, reasons

PATH 3 - SCHEDULED REPORTS (API quota = 0)
SmartMoving scheduled email -> n8n IMAP/Gmail -> parse xlsx/csv -> INSERT into raw_smartmoving.report_*
Uses: storage, historical backfill, total cross-checks with dbt tests
```

Golden rule: **all three paths write to the same raw tables with idempotent merge by primary key**. Replaying an event, sweep, or report never duplicates rows, so reconciliation is always safe.

API implementation notes:

- Date filters use integer `YYYYMMDD`; timestamps `*_Utc` are ISO strings. Normalize in staging, never in marts.
- Paginate until `lastPage=true` with `PageSize=200`; the server caps page size at 200 and each page counts as a call.
- `GET /api/customers` with `IncludeOpportunityInfo=true` is the cheapest sweep: customer -> opportunities -> jobs in one paginated pass. It is the reconciliation backbone. Real latency is 3-6 s/page, so do not parallelize aggressively.
- Back off on 5xx and hard-stop on 4xx; 4xx responses also consume quota.

---

## 3. Strategy By Entity

| Entity | Primary mechanism | Backup / reconciliation | Freshness | Estimated quota |
| --- | --- | --- | --- | --- |
| **New leads** | Poll `GET /api/leads?From=today&IncludeBad&IncludeLost` every 15-30 min | Nightly lead sweep `[-7,0]` | 15-30 min | ~3,000/month |
| **Lead/opportunity status** | `opportunity-created` / `opportunity-status-changed` / `opportunity-changed` webhooks -> debounced enrichment | Hourly service-date window + nightly sweep | Minutes | Included in enrichment |
| **Upcoming jobs, 10 days** | Job/service/opportunity webhooks -> enrichment | Hourly `customers?FromServiceDate&ToServiceDate` detects disappeared jobs and date moves | Minutes; <=1 h guaranteed | ~3,000/month sweeps |
| **Booked opportunities by book date** | `opportunity-status-changed` + event `received_at`; `dim_status_map.is_booked` classifies `leadStatus` | Historical booked-opportunities report; sparse audit calls if needed | Minutes | Marginal |
| **Follow-ups** | Follow-up webhooks -> opportunity followups endpoint | Refreshed with opportunity enrichment | Minutes | Low |
| **Payments** | `payment-made` webhook -> payments endpoint | Daily payments report cross-check | Minutes | Low |
| **Customers** | Customer webhooks -> customer detail | Included through opportunity enrichment | Minutes-hours | Low |
| **Documents** | Read through Include* flags during opportunity enrichment; no document webhook exists | - | Hours | 0 additional |
| **Storage** | No global endpoint; daily storage reports by email | Per-customer storage endpoint for spot checks only | Daily | ~0 |
| **Dimensions** | Weekly cached polling | - | Weekly | ~200/month |

---

## 4. Quota Budget

**Moved to [`crm_sync_contract.md`](crm_sync_contract.md) section 7.**

The budget table that used to live here was superseded twice and each time a stale copy
survived in another file. The contract now holds the only version, and
`scripts/check_sync_contract.py` fails the build if a second one appears.

What is still true, and belongs to this document because it is design rather than
arithmetic:

Spend controls:

- **Internal call ledger** (`scripts/api_call_log.jsonl`): `sm_client.py` records every request with instance, endpoint, page, timestamp, status, rows, and duration.
- **Prorated kill-switch:** if usage exceeds 85% of the prorated monthly budget, n8n pauses low-priority enrichment and lengthens debounce windows. Cheap critical leads/jobs sweeps never pause.
- **Mandatory debounce:** UI edits can create bursts of `opportunity-changed`; coalesce N events for the same resource into 1 call.
- **Automatic call-pack purchases disabled.** Purchase only after reviewing the ledger.
- **Measured July 2026:** `local` had already used 45% of its quota by July 18 from an existing integration; remove or reduce that consumer before scaling the pipeline. `ld` was around 6%.

---

## 5. Webhook Reliability

The SmartMoving 7-day webhook history is only for manual debugging; it is not part of recovery. We keep our own event history:

1. **Immediate raw event persistence.** n8n inserts every event into `raw_smartmoving.webhook_events` before processing and returns 200 immediately. If enrichment fails, the event remains available for retry.
2. **Reconcile by diff, not trust.** Hourly and nightly sweeps compare the API result with the warehouse state. Any discrepancy enters the same enrichment queue.
3. **No duplicates by design.** Events are append-only with hash dedupe; resource tables use dlt merge by composite PK + `snapshot_at`; dbt selects the latest snapshot.
4. **Deletes.** Webhook deletes and sweep disappearances become soft-delete markers. Raw never physically deletes.
5. **Silence detection.** Freshness checks alert if no opportunity events arrive during business hours or if sweeps find many diffs that no webhook reported.

---

## 6. Scheduled Reports

Reports are complementary, not redundant. They provide:

1. **Coverage:** storage and some UI/report-only fields are not exposed by the API.
2. **Zero-quota historical backfill:** All Time reports can load 12-24 months without API calls.
3. **Continuous audit:** dbt tests compare report totals with API-derived marts.

Automation: SmartMoving emails the report on a schedule -> n8n IMAP/Gmail filters by sender/subject -> parses xlsx/csv -> inserts into `raw_smartmoving.report_*` or drops files in a landing directory. Sample files in `smartmoving_scheduble_reports/` are the column ground truth for parsers.

---

## 7. Orchestration In dlt + n8n

**n8n is the Phase 1 orchestrator.** Dagster is deferred per `CLAUDE.md` until n8n scheduling becomes the bottleneck.

- **n8n schedules:** `leads_today_poll`, `jobs_window_sweep`, `nightly_reconciliation`, and `weekly_dims`. Each invokes `pipeline/run.py --job ... --instance ...` across instances.
- **Webhook receiver:** n8n Webhook -> secret header validation -> INSERT into `raw_smartmoving.webhook_events` -> 200. A second schedule reads unprocessed events, debounces by resource id, and triggers enrichment.
- **Retries:** dlt backs off on 5xx; repeatedly failing events go to `raw_smartmoving.webhook_events_deadletter` and alert without blocking the queue.
- **Alerts:** source freshness, webhook silence, and ledger budget alerts through the team's chosen n8n channel.

---

## 8. Phased Implementation Plan

**Phase 0 - Foundations.** Postgres, schemas, roles, RLS, API secret, dlt client with pagination + ledger, seeds, and `pipeline/run.py --dest postgres`.

**Phase 1 - Anchor cases with polling only.** `serving.leads_today_v1` and `serving.jobs_upcoming_v1`, with 300-400 calls/day and dbt uniqueness/not-null/referential tests.

**Phase 2 - Webhooks.** n8n receiver -> `raw_smartmoving.webhook_events` -> debounced enrichment. Jobs and status freshness move from <=1 h to minutes. Sweeps become reconciliation. Add `booked_by_book_date_v1` from `opportunity-status-changed` + `dim_status_map.is_booked`.

**Phase 3 - Automated Scheduled Reports.** Email -> n8n -> `raw_smartmoving.report_*`; daily storage/payments reports; historical booked/all-jobs backfill; dbt report-vs-API checks.

**Phase 4 - Hardening.** Quota kill-switch, deadletter + replay, freshness checks, silence alerts, full historical backfill. Evaluate Dagster or a more robust receiver only if their triggers are crossed.

---

## 9. SmartMoving-Specific Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Exhausting the 125k quota | Internal ledger + prorated 85% kill-switch + debounce + zero-quota reports; retire existing high-volume app before scaling; never API full-sync |
| No modified-date filter | Only date-window sweeps; immutable raw allows reprocessing without API calls |
| 7-day webhook history | Own event history in `raw_smartmoving.webhook_events`; reconciliation within hours |
| ID-only webhook payloads and event bursts | Mandatory debounced enrichment by resource id; idempotent merge |
| n8n receiver outage | Sweeps recover within <=1 h for near-term jobs; uptime monitoring; stronger receiver in Phase 4 if needed |
| No lead-created webhook | Poll leads every 15-30 min |
| Inconsistent date/types | Centralize normalization in staging dbt |
| Report schema drift | Raw JSONB/original columns + versioned parser + dbt schema tests |
| Physical deletes in SmartMoving | Soft-delete by webhook and sweep disappearance; raw never deletes |

---

## 10. Raw Layer Modeling And Timezones

### 10.1 API Shape Or Report Shape?

**Rule: raw faithfully mirrors each source's native shape; the wide "everything" row is a dbt model, never a raw table.**

| Layer | Shape | Why |
| --- | --- | --- |
| `raw_smartmoving.*` API | API JSON as-is, normalized by dlt into parent/child tables with automatic FKs; volatile payload preserved in JSONB where useful | Lossless and replayable |
| `raw_smartmoving.report_*` | Flat export columns exactly as received | Report fidelity and cross-checks |
| `core` / `marts` | `mart_opportunity_360`, one wide row per opportunity joining opportunities, jobs, customer, payments, follow-ups, dimensions, and report-only fields | Rebuilt at zero API cost when logic changes |
| `serving` | Versioned documented views (`serving.<entity>_v1`) with `entity_id` + `synced_at` | Public app contract, RLS by `entity_id` |

Concrete decisions:

- **Opportunity enrichment uses all `Include*` flags** because they do not change quota cost. One call brings maximum available detail.
- **Customer is intentionally thin.** The detail hangs from opportunity, matching SmartMoving's model: Customer -> Opportunity -> Job. Build the 360 at opportunity grain.
- **`status` int vs `leadStatus` string are separate systems.** Business classification uses trimmed `leadStatus` joined to `dim_status_map`.
- **Lead -> `opportunityId`:** `/api/leads` does not include `opportunityId`; dbt builds `int_lead_opportunity_map` using customer email/phone + branch + serviceDate + conversion window until a test proves an exact key.
- **Optional forensic raw JSON:** keep the raw JSON response before dlt if replay without API calls becomes necessary.

### 10.2 Multi-Tenant Timezones

**Rule: UTC is the stored truth; local time is derived, never the source of record.**

1. Raw and staging stay in UTC. API `*_Utc` fields parse as UTC `timestamptz`.
2. Timezone authority is `core.branches.timezone` (IANA, e.g. `America/Los_Angeles`). `dim_instance.timezone` is only a fallback default before branch timezone is resolved.
3. dbt derives local columns in staging/core, such as `created_at_local`, while marts and serving expose both `*_utc` and `*_local`.
4. Daily business metrics always use local date, not UTC date.
5. `serviceDate` (`YYYYMMDD`) is already a local business date and must never be timezone-converted.
6. If a branch timezone changes, edit the seed/source feeding `core.branches.timezone` and rerun dbt. No API calls are needed.

---

## 11. Implementation Verification

1. `GET /api/ping` and poll leads with `PageSize=5`; compare same-day count to SmartMoving UI.
2. Run `python run.py --job jobs --instance all --dest postgres`; confirm rows in `raw_smartmoving`; rerun and confirm zero duplicates.
3. Simulate a webhook to n8n; confirm raw event insert, enrichment trigger, raw update, and `dbt build` refresh of `serving.jobs_upcoming_v1`.
4. Cancel or reschedule a test job and measure reflection in `serving.jobs_upcoming_v1`.
5. Compare `api_call_log.jsonl` with SmartMoving API Usage after 48 h.
6. Connect as `app_read` and confirm RLS filtering plus no access to `raw_smartmoving`/`staging`.

---

## 12. Report Enrichment And Cascading Updates

Reports enter for API gaps, zero-quota historical backfills, and reconciliation.

### 12.1 When Reports Enter And What They Enrich

Each report lands in its own raw table `raw_smartmoving.report_<name>` with two timestamps: `report_generated_at` and `_ingested_at`. `report_generated_at` governs precedence.

### 12.2 dbt Is The Cascade

**Never update downstream tables by hand.** Each model (`staging -> core -> marts -> serving`) re-derives from sources. When a report brings a newer value and dbt runs, the value flows to `serving` because derived tables are rebuilt, not synchronized manually.

dbt lineage lets us run `dbt build --select source:smartmoving.report_booked+` to rebuild exactly the downstream models affected by that report.

### 12.3 Multi-Source Precedence: Latest Observation Wins, By Field

The same fact can arrive from the API sweep, webhook enrichment, and a report. The most recent observation wins.

| Column | Meaning |
| --- | --- |
| `entity_id`, `external_id` | Business key |
| `field` / observed fields | Observed value |
| `observed_at` | When that fact was true: webhook `received_at`, report `report_generated_at`, or API extraction time |
| `source` | `api_sweep` / `api_webhook` / `report_<x>` for tie-break and audit |

```sql
-- core: latest status observation by opportunity
select distinct on (entity_id, external_opportunity_id)
       entity_id, external_opportunity_id, status, source, observed_at
from   {{ ref('int_opportunity_status_observations') }}
order  by entity_id, external_opportunity_id,
          observed_at desc,            -- 1st: most recent wins
          source_priority              -- 2nd: tie-break if timestamps match
```

- **Field-level precedence, not global precedence.** Live status is authoritative from webhooks, book date from booked reports, and storage only exists in reports.
- **Out-of-order arrival is safe.** A late report with an older `report_generated_at` does not overwrite a newer known value.

### 12.4 Cascade Trigger

When a report lands, n8n writes raw and then triggers `dbt build --select source:smartmoving.report_<x>+`. dbt rebuilds affected lineage, serving views refresh, and consumers see the new value on their next query with updated `synced_at`. Webhooks follow the same pattern after enrichment.

### 12.5 Concrete Example

1. The 06:00 daily All Jobs report shows job #12534 as **Cancelled**, a change missed by webhook.
2. n8n loads the report into `raw_smartmoving.report_all_jobs` with `report_generated_at = 06:00`.
3. n8n triggers `dbt build --select source:smartmoving.report_all_jobs+`.
4. `core.jobs` compares observations; the report observation is newer than the last API sweep, so Cancelled wins.
5. `serving.jobs_upcoming_v1` rebuilds and now shows the job as Cancelled with `synced_at = 06:00`.
6. Any app reading `serving` sees the change on its next query without manual synchronization.

### 12.6 Implementation Path For Reports

1. Add one `stg_smartmoving__report_<x>` model per report, using sample columns from `smartmoving_scheduble_reports/`.
2. Add an intermediate `int_<entity>_observations` model unifying API and report observations with `observed_at` + `source`.
3. Refactor `core.<entity>` to latest-observation-wins using `observed_at`, `source`, and `distinct on`.
4. Trigger selective dbt builds from n8n when each report lands.
5. Add dbt cross-check tests: report totals vs API-derived marts.
