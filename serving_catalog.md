# Serving catalog

The published catalog of `serving` views - the contract other teams build on. **A view that is not catalogued does not exist.** Consumers connect with the read-only `app_read` role (RLS-scoped by `entity_id`); see `consuming_serving_data.md`.

Change policy: additive changes ship freely; breaking changes (rename, type change, removal) require a new version suffix with the previous version kept live for 90 days.

---

## `serving.jobs_upcoming_v1`

| Field | Value |
|---|---|
| **Business area** | Operations |
| **Contents** | Every job scheduled in the next 10 days, one row per job. |
| **Grain** | `(source_instance_id, external_job_id)` - one row per job. |
| **Source systems** | SmartMoving (windowed service-date sweep -' `core.jobs`). |
| **Freshness target** | < 15 min. *Current mechanism:* hourly service-date sweep (Phase 1). Drops to minutes once webhook enrichment lands (Phase 2). Read `synced_at` for the actual per-row freshness. |
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
| `status` | text | Opportunity status label. `Booked` is reliable; other values render as `status_<int>` pending a full enum mapping (see `smartmoving_api_findings.md`). |
| `service_date` | date | Local business date of the job (never timezone-converted). |
| `days_until_service` | int | `service_date -' today` (today in the entity's timezone). |
| `service_type_name` | text | Resolved from the job's service-type id (e.g. Moving, Packing, Commercial). |
| `customer_name` | text | |
| `customer_phone` | text | |
| `customer_email` | text | |
| `customer_address` | text | |
| `synced_at` | timestamptz | When this row's source data was last extracted (data freshness). |

**Not yet included** (arrive later via opportunity enrichment, as additive columns - no version bump): branch, origin/destination addresses, crew/dispatch, estimated total. The `status` label mapping will be completed as the sweep status enum is cross-referenced against the UI.

**dbt tests:** not-null on `job_key`/`entity_id`/`external_job_id`/`service_date`/`synced_at`; unique on `job_key` (grain); not-null + unique enforced on `core.jobs` upstream. RLS cross-entity isolation verified.

---

## `serving.leads_today_v1`

| Field | Value |
|---|---|
| **Business area** | Sales |
| **Contents** | Leads created today (entity-local date), one row per lead. |
| **Grain** | `(source_instance_id, external_lead_id)` - one row per lead. |
| **Source systems** | SmartMoving (`/api/leads` windowed poll -' `core.leads`). |
| **Freshness target** | < 15 min. *Current mechanism:* poll every 15 - 30 min (no lead webhook exists). Read `synced_at` for per-row freshness. |
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
