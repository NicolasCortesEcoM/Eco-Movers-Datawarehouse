# Serving catalog

The published catalog of `serving` views - the contract other teams build on. **A view that is not catalogued does not exist.** Consumers connect with the read-only `app_read` role (RLS-scoped by `entity_id`); see `consuming_serving_data.md`.

Change policy: additive changes ship freely; breaking changes (rename, type change, removal) require a new version suffix with the previous version kept live for 90 days.

**Freshness targets are defined in [`crm_sync_contract.md`](crm_sync_contract.md) section 8 and are not restated here.** Each entry below names the entity whose target applies; read the number there. This file once carried its own copies and they drifted out of date - a target stated in two places is a contradiction waiting to happen. `synced_at` on every view is the per-row truth regardless of any target.

---

## `serving.jobs_upcoming_v1`

| Field | Value |
|---|---|
| **Business area** | Operations |
| **Contents** | Every job scheduled in the next 10 days, one row per job. |
| **Grain** | `(source_instance_id, external_job_id)` - one row per job. |
| **Source systems** | SmartMoving (windowed service-date sweep -' `core.jobs`). |
| **Freshness** | Governed by the **Jobs** row of [`crm_sync_contract.md`](crm_sync_contract.md) section 8 (mechanism: service-date sweep plus the `job-closed` enrichment trigger). Read `synced_at` for the actual per-row freshness. |
| **Owner** | Reporting Manager / data-platform team. |
| **Version** | v1 (first published contract). |
| **RLS** | Filtered by `entity_id`; consumers only see their own entity. |

**Columns**

| Column | Type | Notes |
|---|---|---|
| `job_key` | text | Stable unique row id (`source_instance_id`+`external_job_id`). |
| `entity_id` | text | Business entity (RLS key). |
| `source_instance_id` | text | Which SmartMoving instance produced it (`ld` = Long Distance, `local` = Local+Commercial). Doubles as a line-of-business hint. |
| `external_job_id` | text | SmartMoving job id (unique within its instance). |
| `job_number` | text | Human-facing job number (e.g. `12534-1`). |
| `quote_number` | text | Human-facing opportunity/quote number. |
| `status` | text | Opportunity status label, resolved from the authoritative status integer through the `dim_opportunity_status` seed: `NewLead`, `LeadInProgress`, `Opportunity`, `Booked`, `Completed`, `Closed`, `Cancelled`, `Lost`, `BadLead`. A value ever rendering as `status_<int>` means an unmapped code appeared and is a bug, not a placeholder. **Do not derive "booked" by string-matching this column** - `Completed` and `Closed` also count as booked. See [`status_model.md`](status_model.md). |
| `service_date` | date | Local business date of the job (never timezone-converted). |
| `days_until_service` | int | `service_date -' today` (today in the entity's timezone). |
| `service_type_name` | text | Resolved from the job's service-type id (e.g. Moving, Packing, Commercial). |
| `customer_name` | text | |
| `customer_phone` | text | |
| `customer_email` | text | |
| `customer_address` | text | |
| `synced_at` | timestamptz | When this row's source data was last extracted (data freshness). |

**Not yet included** (arrive later as additive columns - no version bump, tracked as P7 in `IMPLEMENTATION_STATUS.md`): branch, structured origin/destination addresses, crew/dispatch, estimated total. Structured addresses come from the All Jobs scheduled report, not from any API source - the enriched payload carries flat address strings whose order does not identify origin vs destination.

**dbt tests:** not-null on `job_key`/`entity_id`/`external_job_id`/`service_date`/`synced_at`; unique on `job_key` (grain); not-null + unique enforced on `core.jobs` upstream. RLS cross-entity isolation verified.

---

## `serving.leads_today_v1`

| Field | Value |
|---|---|
| **Business area** | Sales |
| **Contents** | Leads created today (entity-local date), one row per lead. |
| **Grain** | `(source_instance_id, external_lead_id)` - one row per lead. |
| **Source systems** | SmartMoving (`/api/leads` windowed poll -' `core.leads`). |
| **Freshness** | Governed by the **Leads** row of [`crm_sync_contract.md`](crm_sync_contract.md) section 8. Leads are **polling-only** - SmartMoving has no lead-created webhook, so no mechanism change will make this faster than the poll. Read `synced_at` for per-row freshness. |
| **Owner** | Reporting Manager / data-platform team. |
| **Version** | v1. |
| **RLS** | Filtered by `entity_id`. |

**Columns**

| Column | Type | Notes |
|---|---|---|
| `lead_key` | text | Stable unique row id (`source_instance_id`+`external_lead_id`). |
| `entity_id` | text | RLS key. |
| `source_instance_id` | text | `ld` / `local` (line-of-business hint). |
| `external_lead_id` | text | SmartMoving lead id (unique within its instance). |
| `customer_name` | text | |
| `customer_phone` | text | |
| `customer_email` | text | |
| `referral_source` | text | Marketing source name (e.g. Google, Facebook, Referral Source). |
| `sales_person` | text | Assigned salesperson (nullable). |
| `branch_name` | text | |
| `move_size` | text | e.g. `1 Bedroom`, `2 Bedroom Apartment`. |
| `service_date` | date | Requested move date (nullable; `0` in source -' null). |
| `origin_city` / `origin_state` / `origin_zip` | text | |
| `destination_city` / `destination_state` / `destination_zip` | text | |
| `lead_disposition` | text | `New` / `In Progress` / `Lost` / `Bad Lead` - derived from the reason fields (reliable), not the raw status int. |
| `lost_reason` | text | Present when Lost. |
| `bad_lead_reason` | text | Present when Bad Lead. |
| `created_at_utc` | timestamptz | Lead creation instant (UTC). |
| `created_at_local` | timestamp | Creation in the entity's local time. |
| `synced_at` | timestamptz | Data freshness. |

**dbt tests:** not-null on `lead_key`/`entity_id`/`external_lead_id`/`created_at_utc`/`synced_at`; unique on `lead_key`; enforced on `core.leads` upstream. RLS verified.
