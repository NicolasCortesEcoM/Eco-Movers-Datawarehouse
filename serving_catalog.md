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

## `serving.sales_agent_daily_v1`

| Field | Value |
|---|---|
| **Business area** | Sales |
| **Contents** | Sales performance per agent, line of business and lead-arrival day, 2023-01-01 onward. |
| **Grain** | `(entity_id, agent_name, line_of_business, lead_received_date)` - a COHORT row: it describes what became of the leads that arrived that day, whenever the outcome landed. |
| **Source systems** | SmartMoving (scheduled reports + API sweep -> `core.opportunities` -> `marts.fct_agent_leads_daily`). |
| **Freshness** | Governed by the **Opportunity money / detail** row of [`crm_sync_contract.md`](crm_sync_contract.md) section 8. Read `synced_at` for per-row freshness. |
| **Owner** | Reporting Manager / data-platform team. |
| **Version** | v1 (first published contract). |
| **RLS** | Filtered by `entity_id`. |

⚠️ **Recent cohorts are not comparable to old ones.** Leads from the last few weeks
have not had time to be lost, so their conversion is inflated - August 2026 read 71%
against a 45-50% baseline. Exclude the last ~60 days, or display `open_leads` beside
the rate.

⚠️ **Do not slice by `is_within_assignment` yet.** It records whether the lead landed
in a line the agent was rostered for on that date, and reads `false` for 42% of leads
because `dim_agent_assignment` was built for 2026 and the 2023-2025 history falls
outside its validity windows. It is a data-quality signal until that seed is extended.

| Column | Type | Notes |
|---|---|---|
| `agent_day_key` | text | Grain key. Readable concatenation, not a hash. |
| `entity_id` | text | Business entity (RLS key). |
| `agent_name` | text | Canonical name from `dim_agent`. Group by this, never by the raw CRM string. |
| `is_sales_agent`, `role` | bool / text | From the hand-maintained roster. 34 of 65 CRM names are not yet in it and surface with `is_known = false` upstream. |
| `line_of_business` | text | `local`, `long_distance`, `commercial`, `unclassified`. |
| `lead_received_date` | date | The cohort date. |
| `leads_received`, `valid_leads`, `bad_leads` | int | A bad lead was never winnable and is excluded from the conversion denominator. |
| `booked_leads`, `lost_leads`, `cancelled_leads`, `open_leads` | int | `open_leads` is the cohort-maturity signal. |
| `conversion_pct` | numeric | `booked / valid`, null when there is no denominator. |
| `invoiced_deals` | int | Booked deals carrying a realised figure - the denominator for the average below. |
| `avg_invoiced_deal_size` | numeric | **Realised** revenue per billed deal. Deliberately not based on `estimated_final_total`, which is zero on 45% of booked opportunities and would report $1,151 against a true $2,085. |
| `booked_estimated_value` | numeric | Quoted value of booked deals. Understated for the same reason - prefer `invoiced_value`. |
| `invoiced_value` | numeric | The only realised revenue in the warehouse. |
| `lost_to_competitor`, `lost_on_price`, `lost_no_contact`, `lost_to_diy` | int | Loss reasons from `dim_status_map`. |
| `lost_reason_unknown` | int | Lost with no subcategory resolved - 4.4%. A rise means the CRM emitted a status the seed does not know. |
| `avg_minutes_to_first_contact` | numeric | Only the Lost Leads report carries this, so it is populated for lost records only. |
| `is_within_assignment` | bool | See the warning above. |
| `synced_at` | timestamptz | Data freshness. |

## `serving.lead_source_daily_v1`

| Field | Value |
|---|---|
| **Business area** | Sales / Marketing |
| **Contents** | Lead volume, quality and conversion per marketing channel, line of business and lead-arrival day, 2023-01-01 onward. |
| **Grain** | `(entity_id, channel_group, line_of_business, lead_received_date)` - the same cohort grain as `sales_agent_daily_v1`. |
| **Source systems** | SmartMoving `referral_source`, classified through the `dim_referral_source` seed. |
| **Freshness** | Governed by the **Opportunity money / detail** row of [`crm_sync_contract.md`](crm_sync_contract.md) section 8. |
| **Owner** | Reporting Manager / data-platform team. |
| **Version** | v1. |
| **RLS** | Filtered by `entity_id`. |

⚠️ **`channel_group = '(unmapped)'` is a real bucket, not an error.** It carries the
CRM referral sources the seed does not yet classify - around 6,200 opportunities
converting at 41%. Filtering it away silently removes a tenth of the funnel.

**This is where marketing spend attaches.** Once ad cost lands at
`(date, channel_group)`, cost-per-lead, CAC and ROAS are joins onto this table rather
than new models. `any_paid_source` says whether a cost denominator should exist at all.

| Column | Type | Notes |
|---|---|---|
| `source_day_key` | text | Grain key. |
| `entity_id` | text | RLS key. |
| `channel_group` | text | Paid Search, Paid Social, GBP, Organic, Referral, Affiliate, Direct, AI, Local Services, Unknown, `(unmapped)`. |
| `referral_platform` | text | Google / Meta / Bing / Yelp / …, and **null when the group mixes platforms** - `Paid Search` spans Google and Bing, and labelling a mixed group with one of them would be a fabrication. |
| `any_paid_source` | bool | True when any lead in the group came from a source that needs spend. |
| `line_of_business`, `lead_received_date` | text / date | |
| `leads_received` … `open_leads` | int | Same definitions as the agent view. |
| `conversion_pct`, `bad_lead_pct` | numeric | Conversion is against **valid** leads; bad-lead rate is against everything received. |
| `invoiced_deals`, `avg_invoiced_deal_size`, `booked_estimated_value`, `invoiced_value` | numeric | Same money caveats as the agent view. |
| `lost_to_competitor`, `lost_on_price`, `lost_no_contact` | int | Loss reasons from `dim_status_map`. |
| `synced_at` | timestamptz | Data freshness. |

