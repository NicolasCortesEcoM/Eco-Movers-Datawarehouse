# SmartMoving API - Live Exploration Findings

> Exploration from 2026-07-18 against the two real instances: 33 total calls logged in `scripts/api_call_log.jsonl`. This document is the **ground truth** that complements `smartmoving_api_complete_reference.md` (scraped docs) with behavior only visible against the live API. Update it whenever we learn something new.

## Instances

| Instance | Branches | Users | Volume (45 days of leads) | Jobs in next 10 days |
| --- | --- | --- | --- | --- |
| `ld` (Long Distance) | Main Office, South Sound LD | 9 | 197 leads (1 page) | 66 customers / ~60 opps |
| `local` (Local + Commercial) | Bremerton, Kirkland, Long Distance Team, Lynnwood, Seattle, South Sound | 20 | **>600 leads** (stopped at 3 pages, ~13+/day) | 395 customers / ~400 opps / ~490 jobs |

- The `local` instance has a branch named "Long Distance Team". This confirms the warning in seed `SCRDLA - dim_lob_map.csv`: **branch_name is not reliable for LOB classification**; instance and service type are reliable.

## Live-Confirmed API Behavior

1. **`PageSize` is capped at 200 by the server.** We requested 500 and received 200 per page with no error. Budget pages using 200, not more.
2. **Latency:** `/api/leads` is ~300-500 ms/page; `/api/customers` with `IncludeOpportunityInfo` is heavy at **3-6 s/page**. Serialize calmly; do not parallelize aggressively.
3. **`/api/ping`** returns server build `Build Number: 20260707.30`, identical on both instances.
4. **Real volumes for budgeting:** the +10 day jobs sweep costs 1 page (`ld`) and 2 pages (`local`), so the strategy estimate of ~4 calls/sweep is correct. Same-day leads polling will almost always cost 1 page per instance.
5. **Short-window rate limit confirmed on 2026-07-22, in addition to monthly quota.** An enrichment burst (`GET /api/opportunities/{id}` serially) returned **`429 "Rate limit is exceeded. Try again in 33 seconds."`** after ~121 calls in <60 s. The undocumented limit is around **~120 calls/minute**. This corrects the earlier assumption that there was no per-second/minute rate limit. Mitigation implemented in `sm_client.py`: 429 is retryable and respects `Retry-After` / "try again in N seconds"; `run.py --pace` provides proactive pacing around 0.6 s/call (~100/min). 429 responses consume quota, so proactive pacing is better than reacting.

## Resolved Enums (scrape showed `{}`)

### `type` fields are ids from `/api/service-types`

`lead.type`, `opportunity.type`, and `job.type` join directly to `GET /api/service-types`. Values seen in `local`: 1=Moving, 3=Packing, 5=Load Only, 6=Unload Only, 7=Commercial, 8=Storage In Bound, 9=Storage Out Bound, 106=Moving and Unpacking. Each instance has its own list; ids can overlap but differ, so the dimension is per instance. `lead.type` can be `null` (85 of 685 leads).

### Numeric `status` (lead and opportunity) is platform enum, not custom pipeline

- Seen `lead.status`: `0`, `1`, `30`, `50`. Distribution across 45 days, both instances: 30 -> 589, 50 -> 149, 1 -> 58, 0 -> 1. Strong hypothesis to verify in UI: `0` = New, `1` = In Progress, `30` = Lost/Bad grouped, `50` = another terminal state. **Pending:** map each int by comparing concrete records with the UI.
- Seen `opportunity.status`: `3`, `4`, `10`, `20`, `30`, `50`; future windows are dominated by 4 and 30.
- **Business key:** opportunity detail includes **`leadStatus` as a string with the custom pipeline status name**. These are the same names as `GET /api/leads/statuses`: CMET, Follow Up, Booked, Tentative Booking, Wait list, Lead Reservoir, Wellness Check, Bad Lead, etc. This string joins to `SCRDLA - dim_status_map.csv`. The int and string are separate systems: int is platform status, string is configurable pipeline status.

### `/api/leads/statuses` returns the custom pipeline (GUID + name)

Both instances have 10 custom statuses with identical lists, which is good for the seed. Note: `"Booked "` includes a trailing space, so normalize with `TRIM()` in staging before joining to `dim_status_map`.

## Real Shape Of Full Opportunity (all `Include*` flags)

Payload from `GET /api/opportunities/{id}` with all 10 flags: embedded `customer` (id, name, contact), `branch`, `contacts[]`, `moveSize` with volume, `volume`/`weight`, `estimatedTotal` (subtotal/tax/finalTotal), `salesAssignee`, `referralSource`, `customField01-03`, `cancellationReason`, `jobs[]`, `payments[]`, `tripInfo`, `opportunityFiles[]`, `photos[]`, `opportunityDocuments[]`, `surveys[]`, `tasks[]`, `tariff`, `createdAtUtc`, and valuable **`leadStatus`** string. This is the source for `mart_opportunity_360`.

## Confirmed Type Inconsistencies (normalize in staging)

| Field | Where | Real type |
| --- | --- | --- |
| `serviceDate` | `/api/leads`, opportunity detail | integer `YYYYMMDD` (`20260819`) |
| `jobs[].serviceDate` | `/api/customers?IncludeOpportunityInfo` | **ISO string** `"2026-07-20"` |
| `quoteNumber` | `/api/customers` | string `"135843"` |
| `quoteNumber` | opportunity detail | **integer** `135843` |
| `status` in leads/opps | lists | integer platform enum |
| `leadStatus` | opportunity detail | string custom pipeline, may contain spaces |

## Downloaded Dimensions (snapshot in exploration log)

referral-sources: 70 (`ld`) / 99 (`local`), direct input to validate `SCRDLA - dim_referral_source.csv`. move-sizes: 42/34. tariffs: 1/1. lost-reasons: 13/13. bad-lead-reasons: 13/13. cancellation-reasons: 6/7. arrival-windows: 7/4. users: 9/20.

## UI Exploration (2026-07-19, Playwright, both instances)

### Webhooks - event list confirmed

The Add Webhook modal offers exactly the **17 documented events**: Opportunity Created/Status Changed/Changed/Deleted, Follow Up Created/Completed/Changed/Deleted, Payment Made, Customer Created/Updated, Job Created/Deleted/Finalized/Closed/Reset, Service Type Changed.

- **There is no lead-created or document webhook.** The polling strategy for leads is definitively validated.
- The webhook supports **Custom Headers**; use them to authenticate the n8n receiver with a secret header.
- **Already active webhooks** (Path 1 is partially underway):
  - `local`: webhook URL in laptop `.env` as `smartmoving_webhook_url` -> Opportunity Status Changed since 2026-07-04, plus Zapier -> Job Closed.
  - `ld`: same n8n endpoint -> Opportunity Status Changed since 2026-07-07, plus `app.qubesheets.com/api/external/smartmoving` -> Opportunity Created.

### Current Quota Consumption (read from API Usage on July 18)

| Instance | Used | % | Projected pace |
| --- | --- | --- | --- |
| `local` | **56,626 / 125,000** | **45%** | ~97k/month; something is already consuming heavily (Zapier/qubesheets/n8n?) |
| `ld` | 7,703 / 125,000 | 6% | ~13k/month, plenty of room |

**Required action before Phase 1:** identify what integration consumes the ~3,100 calls/day in `local`. If it continues, our strategy (~50k/month) plus that usage would exceed quota. Call packs are $30 per 25,000 calls with rollover.

### Scheduled Reports - mechanics confirmed

- Each report has an Export button with **Recipients (emails) + One Time / Scheduled**.
- Frequencies: **Daily, Weekly, Bi Weekly, Monthly**, with start date and time.
- Range presets: **Today, This Week, This Month, This Quarter, This Year, All Time**, with navigation to prior periods. **All Time = zero-quota historical backfill.**
- Only 1 schedule is active today (`local`: Sales Person Performance weekly -> samia@ecomoversmoving.com). The xlsx files in the repo were manual exports; **Path 3 schedules still need to be created**.
- Smart Insights catalog: All Jobs, Booked Opportunities by Date Booked, Cancellation Details, Lead Status, Lead Source and Conversion Analysis, Marketing ROI, New Leads, Payments, Refunds, Revenue Forecast, Sales Person Performance, Storage Accounts, Profitability Details, Accounting Job Revenue, Additional Services Sold, and more. Custom Insights require plan upgrade; standard reports are enough for Path 3.

### `opportunity.status` Mapping (int -> name) - in progress

Cross-checking UI quote numbers against the API (2 calls):

| Int | UI name | State |
| --- | --- | --- |
| 4 | Booked | confirmed, 2 records |
| 11 | Closed | confirmed |
| 3, 10, 20, 30, 50 | ? | pending; each new UI/API cross-check fixes another |

Also confirmed: `status` (platform int) and `leadStatus` (custom pipeline string) are **independent systems**. A Closed opportunity (11) keeps `leadStatus='Booked'`.

- **The `status` enum from the `/api/customers` sweep does not match the detail endpoint `/api/opportunities`.** In the upcoming-10-days jobs sweep from the 2026-07-21 dbt build, observed `opportunity.status` values were **4** (Booked, 314 jobs), **30** (188), **20** (71), **3** (45), **10** (8), **50** (6), and no `11`. But the detail endpoint returned `11=Closed` for a quote the sweep reported differently. The same field has **different codings by endpoint**. Only `4=Booked` appears stable across both. Map sweep ints (3, 10, 20, 30, 50) separately by crossing sweep quoteNumbers with the UI. Until then, `serving.jobs_upcoming_v1.status` shows them as `status_<int>`.

## Pending Verification

1. **Identify the consumer of ~3,100 calls/day in `local`** (Zapier? qubesheets? n8n?) before adding our pipeline.
2. Complete the `status` int mapping: 3, 10, 20, 30, 50. Cheap method: cross UI reports vs API by quoteNumber.
3. **Lead -> opportunity test (2 calls):** convert a test lead and compare IDs to decide exact vs heuristic mapping.
4. Review the existing n8n flow `smartmoving-webhook`: what it currently does with Opportunity Status Changed events; it may be the base for the Path 1 receiver.
