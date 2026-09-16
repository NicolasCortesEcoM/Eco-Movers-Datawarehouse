# Implementation Status - the plan of record

> **How to use this document.** The single reference for where the warehouse is, what is
> done, what is open, and what comes next. Mark items done with the date; keep "Next
> actions" current. Architecture lives in `CLAUDE.md`, `ARCHITECTURE.md`,
> `crm_sync_contract.md` and `decisions/`; task-level detail for the 2026-09 audit lives
> in `AUDIT_PLAN.md`. This file is deliberately condensed: completed work is a line, not
> a story. Rewritten in English on 2026-09-15.

**Last updated:** 2026-09-15
**Repository:** `https://github.com/NicolasCortesEcoM/Eco-Movers-Datawarehouse`
(branch `warehouse-audit-and-sales-kpis`, PR to `main` pending)

---

## 1. Where we are

**Phase 1 (SmartMoving -> Postgres) is complete and operating.** Six serving contracts
published, five ingestion mechanisms running unattended, an external heartbeat watching
all of them. **Phase 2 has started** with the first non-CRM source: Google Ads cost is
in production and attributed per lead.

### The warehouse today

| Table | Rows | Grain |
|---|---:|---|
| `core.opportunities` | 71,914 | one per opportunity (= lead), 60 columns |
| `core.jobs` | 63,576 | one per job, 100 columns |
| `core.lines_of_business` | 63,576 | line of business per job |
| `core.leads` | 36,932 | one per lead received |
| `core.opportunity_charges` | 10,209 | estimated and actual charges |
| `core.payments` | 3,037 | every payment received (scheduled report) |
| `core.opportunity_payments` | 2,006 | payments embedded in the API payload |
| `core.agents` | 68 | sales roster |
| `core.branches` | 8 | branches with time zone |
| `raw_google_ads.campaign_daily` | 413 | Google Ads cost per (account, campaign, day), $39,181 |

Coverage on 71,914 opportunities: lead date 97%, assigned agent 97%, line of business
100%, lost reason 95.6%, marketing channel and campaign family 98.9%, quote number 81%
(the rest drains at ~500/month), cancellation date 1,476 of 6,331 (report window starts
2026-01-02).

`core` also holds `workspace_tasks`, `workspace_projects`, `workspace_departments`
(13,283 rows) written by another application. Reported, never touched.

### Serving contracts (`serving_catalog.md` is the contract)

| View | Rows | Grain |
|---|---:|---|
| `opportunities_v1` | 68,231 | one per in-scope opportunity, 39 columns |
| `sales_agent_daily_v1` | 12,748 | cohort: agent x line x lead-received day |
| `lead_source_daily_v1` | 11,181 | cohort: channel x line x lead-received day |
| `cancellations_daily_v1` | 1,007 | period: agent x line x cancellation day |
| `pipeline_current_v1` | 636 | snapshot of live opportunities |
| `jobs_upcoming_v1` / `leads_today_v1` | 409 / 12 | operational |

### Where each fact comes from

| Source | Cost | Contributes |
|---|---|---|
| Webhooks | free | status, within seconds |
| Scheduled reports (6) | free | money, addresses, agent, cancellations, payments |
| `GET /api/leads` | 1 call / 200 | identity of every lead that never converted |
| API sweep | 1 call / 200 | identity of what did convert |
| API detail | 1 call / opportunity | depth, only when a webhook justifies it |
| Google Ads API | free (Explorer, 2,880 ops/day) | campaign cost per day |

Cadence, quota and what each mechanism cannot do: `crm_sync_contract.md` (authoritative).
Freshness is watched by `pipeline_heartbeat.py` (cron, 6 mechanisms) - the only alert
that can see a job that never ran.

---

## 2. Status by phase

| Phase | Status | Remaining |
|---|---|---|
| Audit A1-A8 (2026-09) | done | A2 root cause not proven under a large historical burst (see §5) |
| Sales KPIs B0-B4 | done 2026-09-14 | - |
| Phase A - Cancellations and Payments in core | done 2026-09-10; ZIP and reason marts done 2026-09-15 | serving views when a consumer exists |
| Phase B - `serving.opportunities_v1` | done 2026-09-14 | - |
| **Phase C - Marketing** | **in progress** | 3 more Google Ads accounts (blocked: no access yet), Meta credentials; Bing live 2026-09-15 |
| Phase D - 13 unused schedulable reports | pending | see §4.2 |
| Phase E - QuickBooks (Intuit Developer API) | scoped, not started | see §3 |
| Tech debt C5-C8 | open | see §4.6 |

---

## 3. Scope

**Phase 1 - SmartMoving (complete).** Two instances (`ld`, `local`), one entity. Raw
stores payloads exactly as received; all typing and business logic in dbt. A lead and an
opportunity are the same record (the lead `id` IS the opportunity GUID); no fuzzy
lead-to-opportunity match may ever be built. Out of scope: notes, follow-ups, interaction
history, audit activity, inventory lines, document URLs, Premium per-job calls.

**Phase 2 - remaining sources.** Each follows `CLAUDE.md` "Adding a new source" to the
letter: API docs, a client with ledger and budget, a dlt resource with composite PK and
merge, `raw_<source>`, staging, core, a row in `crm_sync_contract.md`.

- **Google - ad platforms and Cloud.**
  - Auth is a **Google Cloud service account** in project `ecomovers-datawarehouse`,
    key stored base64 in `.env`, decoded in memory. Since 2026-09-09 the Google Ads API
    access level belongs to the Cloud project (Explorer granted 2026-09-14); the
    developer token is sent but ignored. Any further Google API (Analytics, Business
    Profile, Search Console) reuses the same service account and project.
  - **Google Ads** (live): manager `2797921560` -> child accounts discovered every run;
    one child today (`PNW Moving`, 1776272460). Three more child accounts join when the
    manager grants access; each needs one `--account <id> --from 2023-01-01` backfill.
  - **Meta Ads, Bing Ads**: same mould, a client and a resource each, one more union arm
    in `int_ad_spend_daily`. Platforms without an API (Yelp, Nextdoor...) use the email
    lane through `report_ingest`. Guide: `marketing_ads_integration_guide.md`.
- **QuickBooks** via the **Intuit Developer API** (QuickBooks Online Accounting API,
  OAuth 2.0 from an Intuit Developer app). Target entities: invoices, payments,
  customers, accounts, expenses, and the profit-and-loss / balance-sheet reports, into
  `raw_quickbooks`. Purpose: realised revenue and cost next to the CRM's estimated and
  invoiced figures, and true marketing ROI (spend from ad platforms, revenue from the
  books). Prerequisites Nicolas owns: an Intuit Developer account and app (client id,
  secret, redirect URI), the company realm id, and one OAuth consent by a QuickBooks
  admin (refresh token, 100-day rolling). Crosswalk `quickbooks customer <-> CRM
  customer` is explicit, never inferred. Not started; no code exists yet.
- Later: Paylocity (employee identity anchor), RingCentral (calls; 92% of dialled
  numbers match a CRM phone, measured 2026-09-07).

**Phase 3 - applications on `serving`; Phase 4 - analytical offload only on the
`CLAUDE.md` trigger.** Unchanged.

---

## 4. Open items

### 4.1 Phase C - marketing, what remains

Done: `dim_referral_source.campaign_group` (178 -> 190 sources, 59 families);
`is_paid` = "is a marketing source", list fixed by Nicolas 2026-09-15 (Google Ads all
variants incl. PNW Google Ads and Eco Commercial, Google Guarantee, Bing Ads, Meta,
Yelp all variants, Great Guys, Move Buddha, Snoball, plus the paused YouTube Ads,
OpenAI Ads, Angi Ads, Thumbtack, USA Homelisting; everything else organic - `PNW` is
PNW Moving's organic source); `fct_campaign_daily` (two levels, per-lead split
ready); Google Ads extraction (`pipeline/ads_pipeline/`, `run_ads.py`,
`raw_google_ads`, `stg_google_ads__*`, n8n `ads_google_daily` 06:00 PT, heartbeat);
`dim_ad_campaign_map` (6 rows, all PNW Moving campaigns -> `PNW Google Ads`);
`int_ad_spend_daily` -> `fct_campaign_spend_daily` (CPL, CPA, CER, per-lead split,
`unassigned` line for spend on days without a lead) + `mart_unmapped_ad_spend`;
reconciliation test attributed + unmapped = raw on every build. Verified to the cent
against the Google Ads UI on two days.

**Microsoft Advertising (Bing) live 2026-09-15**: OAuth bootstrap `scripts/msads_oauth.py`,
client `microsoft_ads.py` (async report, JSON endpoints, refresh token rotated per run),
`raw_microsoft_ads`, `stg_microsoft_ads__*`, second union arm in `int_ad_spend_daily`,
n8n `ads_microsoft_daily` 06:10 PT, heartbeat. Backfill: 1,355 campaign-days, 10
campaigns, $107,523 since 2024-10-04 (Microsoft keeps 36 months; the account is
younger). All 10 campaigns mapped per Nicolas (100% of spend: 9 -> `Bing Ads`, `Movers | Bing
Commercial` -> `Bing Ads Commercial`); `Bing` / `Bing <city>` stay organic. Bing CPL 2025:
$61 local, $55 LD, $73 commercial; 2026: $68 / $65 / $60.

**Rule (Nicolas, 2026-09-10):** cost splits per lead, not per the campaign's nominal
line - $100 and 3 leads (1 LD, 2 Local) gives $33.33 / $66.67. Commercial is measured by
its own campaigns, not by line. **Consumers aggregate by month; never average daily CPLs.**

Remaining, in order:
1. **Nicolas**: access to the other three Google Ads child accounts (waiting on the
   manager). They appear on the next run; I backfill each and pre-fill
   `dim_ad_campaign_map` from Nicolas's name reference (guide §6) for confirmation.
2. **Nicolas**: Meta Business System User token (guide §3). Then `meta_ads.py`, its
   resource, one union arm. Meta is the second marketing source (1,331 leads in 2026,
   13% booked vs 32% for Google) - the CPA that changes decisions most.
3. Google LSA (499 leads) by the same mould; Bing is done.
4. `serving.campaign_spend_daily_v1` when a consumer exists (rule: no consumer, no
   serving view; the mart is queryable from Metabase now).

### 4.2 Phase D - the 13 unused schedulable reports

Zero quota: schedule in the SmartMoving UI to a `*reporting@` alias, add the report to
`REPORTS` in `Resolve Report Metadata`, the rest of the lane exists. By value:
`sales-person-activity-details` (feeds the sales KPIs), `outstanding-balances` (AR),
`refunds` (net revenue), `affiliates` (72 of 190 sources are affiliates),
`storage-accounts` + `storage-jobs-report` (326 storage payments in `core.payments` have
no context), `opportunities-by-move-date`, `crew-ratings`, `customer-service-tickets`.

### 4.3 Cancellations by ZIP and by reason - done 2026-09-15

`int_cancellation_detail` (one row per cancellation: geography of the primary job,
reason, lead/booking/move timing, late flag = within 48 h of the move, value, deposit,
crew/hours estimates, mileage band, win-back), `fct_cancellations_by_zip` (cohort by
lead month, WITH denominator, reasons as columns) and `fct_cancellation_reasons_monthly`
(period grain, share of month, timing, cost). Reconciliation test against core. First
reading, 2026: local cancels 20.8% of what it wins, LD 14.6%, commercial 1.3%; 24% of
cancellations happen within 48 h of the move; 55% "no longer needed", 29% "another
mover", 9% price; win-back 2%. Open: no cancellation has a payment on record (deposits
not taken, or refunds leave the report - the Refunds report answers it). Serving views
when a consumer needs them; the marts are readable from Metabase now.

**Payments audit, refunds and outstanding balances - done 2026-09-15.** Audit on the
accumulated `core.payments` (36,890 rows): identical same-day pairs (11) are real split
payments - they reconcile to the invoice to the cent - except 4 whose total is exactly
twice the invoice (duplicate entries, flagged `is_exact_double`); negatives carry no
marker, so `transaction_kind` classifies them by shape: 32 `bounce` (E-Check that
exactly reversed an earlier payment, 26 re-collected later) vs 1,524 `refund`;
overpaid opportunities 40 of 25,680. `marts.fct_refunds_daily` (DAILY base so weekly and
monthly are GROUP BYs; refunds exclude bounces; collected on the same row for rates) and
`marts.fct_outstanding_balances` (one row per unsettled opportunity: invoice = sum of the
jobs' actual cost - the opportunity's own figure is null for 301 ld closed opps -, net
paid from the report or the API, `population` and `balance_kind`, aging from the
completed/service date). First reading: $689K open on 301 invoiced opportunities, 75% of
it 90+ days and mostly commercial / Bill-To-Account customers that settle outside the
CRM - QuickBooks closes that gap. Refund rate 2026: 0.5-1.5% of collected per month.

**Revenue follows All Jobs (Nicolas, 2026-09-15).** `core.opportunities.invoiced_amount`
is now the sum of the opportunity's jobs' Total Actual Cost (All Jobs), Booked report
only as fallback; the old value stays as `booked_report_invoiced_amount`. Effect on
closed/completed revenue: local $43.12M -> $43.45M (+164 opportunities that were never
in a Booked generation), **ld $3.58M -> $5.57M** (+301). Every revenue mart moved with
it. An LD opportunity is settled when Closed or when payments reach that total
(`is_delivery_pending` in the balances mart: 40 today). `mart_payment_discrepancies`
is the work queue for accounting fixes in SmartMoving (never auto-excluded): 4
duplicate-entry suspects, 12 overpaid, 18 paid with no invoice, 2 cancelled holding
money, 4 bounces not re-collected ($12K). Commercial / Bill-To-Account rows with no
CRM payment stay unmarked until QuickBooks AR is crossed with them.

**Booking survival and first-contact speed - done 2026-09-15.**
`int_booking_detail` (booking date from job > Booked report > webhook > lead date as a
measured proxy, source on the row) -> `fct_booking_survival` (share alive N days after
booking, hazard per window; horizons are a var) and `fct_bookings_by_lead_time`
(cancellation rate by how far ahead the booking was made). `core.opportunities`
now reads Time to Contact from the Lead Status report (99% of leads since 2025; before,
only lost leads had it) -> `int_first_contact_timing` (BUSINESS minutes: vars
`business_hours_start/_end/business_days` in dbt_project.yml, 08:00-17:00, seven days -
weekend leads are answered within the hour 61-64% of the time) ->
`fct_first_contact_outcomes` (conversion, cancellation and lost rate by response band).
Booking-date sources, verified 2026-09-15: SmartMoving blanks `Booked at Utc` in All
Jobs once a job is cancelled, so 999 cancellations from 2026-02..07 (before webhooks
on 07-22 and the Booked report on 09-05) have no recorded booking date - a closed
historical window, not an ongoing gap. Source order job > Booked report (any
generation) > webhook > Quote Sent (Nicolas's proxy: median 0 days, p75 0, to the
real booking) > lead date; the source is on every row. The "2+ business days"
response band converting at 59% is warm leads (return customers, word of mouth)
booked on the phone before any logged touch - Time to Contact measures the first
LOGGED communication - and is documented as an artifact in the mart.
First reading, 2026 bookings: 96.2% alive at day 1, 89.3% at day 7, 86.2% at day 14,
~85% from day 21 on; the hazard peaks in days 7-21 (6.6%/window) - that is when to
call. Bookings made 60+ days ahead cancel 38% vs 15% for 0-6 days. Speed: the team
answers in a median 8 business minutes; slow first contact LOSES the lead (lost 43% ->
55%) rather than producing a cancellation later.

### 4.4 The quote drain

2,349 Lead Status quotes without a GUID (2026-09-14, all `local`). Drains itself: 300
per instance per report burst inside `report_ingest`, before the dbt build. **Permanent,
not a backfill** - ~500 non-converting leads/month never enter through the sweep. It
adds enrichment (quote number, estimate, time to first contact, lost subcategory), not
lead count.

### 4.5 Seeds only Nicolas can finish

`dim_agent` (65 rows, 34 DRAFT) and `dim_agent_assignment` (75 rows, 41 DRAFT) were
drafted from lead evidence on 2026-09-14; `is_within_assignment` went 58% -> 99.3%.
Review the DRAFT rows. `dim_lob_branch`: decided 2026-09-14, `Long Distance Team` is
local.

### 4.6 Tech debt

| # | What | Where |
|---|---|---|
| C5 | Booked report join duplicated between `int_opportunity_observations` and `bkd_extra`; the only report without an `int_report_*_latest` | both files |
| C6 | `--max-pages` not propagated to `--job jobs` or dims; silent truncation at 50 pages | `sm_pipeline/source.py` |
| C7 | `--ids` + `--quotes` together emit two resources with one name; rejected in `run.py` only | `run.py` |
| C8 | `dbt_build_reports` cron documented four ways | several |
| - | 8 declared sources nobody reads (`opportunities_enriched__*`) | `_smartmoving__sources.yml` |
| - | Heartbeat repeats instead of escalating (14 identical alerts in 6.5 h) | `pipeline_heartbeat.py` |
| - | `report_ingest`: quarantine an email that fails row-count verification N times instead of retrying it every 2 minutes forever (the A2/A6/A7 pattern) | `deploy/n8n_report_ingest_setup.md` |
| - | Workflow `Cancelled Opportunity` (`fSs1rIV9Ik0m0824`, not ours) has API keys in plaintext | n8n |

---

## 5. Incidents worth remembering (root causes still relevant)

- **2026-09-15 - `core.payments` forgot money nightly.** The Payments export is a rolling
  90-day window and the model took the newest generation whole, so a payment left core
  the day it aged out; raw still had every generation. Fixed by `int_report_payments_all`
  (union all generations, dedupe by transaction identity, `is_current` for edits/voids)
  and by reloading the ranges no generation covered (`scripts/load_report_export.py`).
  Rule since then: **every report-fed table is accumulative** - audited the five keyed
  reports the same day; they already were (`distinct on (key)` across generations).
- **2026-07-22..08-08 - extraction silently dead 17 days.** `platform_rw` lacked
  `CREATE ON DATABASE`, so dlt's merge staging dataset failed *after* the API calls were
  spent; the SSH node piped the exit code away. Fixes: the grant, and every n8n SSH
  command is `out=$(...); rc=$?; ...; exit $rc` with a Code node asserting `rc`.
- **2026-08-13 - 550 false deletions.** Two schedules with different sweep windows;
  absence-based deletion rejected presence proofs older than 2 days since. Never pass
  `--from-offset/--to-offset` to a scheduled run.
- **2026-08-08 - `.env` quoting.** The droplet `.env` single-quotes values for `source`;
  a parser that kept the quotes gave Postgres the user `'platform_rw'`. Both parsers
  strip matched quotes.
- **2026-09-08 (A2) - `report_ingest` OOM crash loop 24 h.** Unbounded IMAP batch,
  per-row inserts, cleanup behind the build. Now: one email per execution, set-based
  landing, cleanup first, alias-filtered Gmail query, unusable mail archived, 4 GB swap.
  Not yet proven under a large historical burst.
- **2026-09-09 (A5) - 13,196 opportunities missing** because three docs said leads and
  opportunities were different records. The lead id is the GUID; `/api/leads` is now an
  observation arm. Every conversion rate had been reading high.
- **2026-09-12..14 (A7) - one email blocked the lane two days**, 1,262 failed
  executions: two rows shared a `Quote #` and `ON CONFLICT DO NOTHING` dropped one, so
  the count never matched. Repeated natural keys are now position-suffixed. Third
  occurrence of "one bad email retried forever" (A2, A6, A7) - hence the quarantine item.
- **2026-09-14 (A8) - `report_bot` lost `ld` All Jobs** on a blank sign-in page; login
  now reloads up to three times.
- **2026-09-15 - campaign labels split on whitespace.** `PNW Google Ads ` (trailing
  space) and `PNW Google Ads` read as two campaigns; the label now falls back to the
  seed's canonical string, never the opportunity's raw one. Five sources were affected.
- **A1 - retention would have deleted 2023-2025 history on 2026-09-17**: the historical
  backfill landed all generations on one calendar day. `_is_historical_backfill` marker,
  excluded from pruning.

---

## 6. Key facts and decisions

- SmartMoving quota 125k/month **per instance**; ~120 calls/min short-window limit.
  `Include*` flags cost nothing; `GET /api/leads/{id}` is byte-identical to a list row
  (never loop it); `PageSize` caps at 200; no `modifiedSince` anywhere - hence the
  hash-diff sweep. No lead-created webhook: leads are polling-only.
- Timestamps `timestamptz` UTC; report `*at Utc` columns are NOT UTC (`DATABASE.md`).
- `serving` is materialised as tables on purpose: `apply_rls` filters on `BASE TABLE`.
- The droplet (`143.198.150.5`) is the environment; deploy with
  `python deploy/sync_droplet.py` (packs the tree, installs `pipeline/requirements.txt`,
  runs seed + build + RLS). Secrets only in `.env`, never on disk elsewhere.
- Google Ads API access level is a property of the Cloud project, not of the developer
  token (since 2026-09-09). Explorer = 2,880 ops/day; a daily run uses ~2.
- Self-hosted Postgres stays until the `CLAUDE.md` trigger fires.

---

## 7. Next actions

| # | Action | Owner | Blocked on |
|---|---|---|---|
| 1 | Grant access to the other three Google Ads child accounts | Nicolas | Google Ads manager |
| 2 | Meta Business System User token | Nicolas | - |
| 3 | Intuit Developer app + QuickBooks admin consent (Phase E prerequisites) | Nicolas | - |
| 4 | Phase D: schedule `sales-person-activity-details` and `affiliates` (Outstanding Balances and Refunds are derivable from Payments + All Jobs - decided 2026-09-15; marts pending Nicolas's go) | Nicolas (UI) + Claude (wire) | - |
| 6 | `report_ingest` quarantine after N failures (§4.6) | Claude | - |
| 7 | Open the PR `warehouse-audit-and-sales-kpis` -> `main` | Nicolas | - |
