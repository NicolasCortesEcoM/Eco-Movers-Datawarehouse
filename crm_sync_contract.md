# CRM Sync Contract

**How SmartMoving data gets into this warehouse, how often, and what it costs.**

---

## ⚠️ This file has precedence

If any other document in this repository contradicts this file, **this file is
correct and the other document is a bug.** Fix the other document; do not "reconcile"
by averaging the two.

This rule exists because the same facts were once written in twelve files and drifted
into six contradictions — cadence stated three ways, quota estimates differing by
2.6×, a lead webhook that does not exist. Anyone reading the repo, human or AI, would
have picked whichever copy they opened first.

**The corollary is a rule for editors:** do not copy numbers out of this file into
another document. Link here instead. A number that exists in two places is a
contradiction waiting to happen.

The only file that outranks this one is [`smartmoving_api_findings.md`](smartmoving_api_findings.md),
and only for raw measurements of the vendor API — this contract cites it rather than
restating it. The scraped vendor docs under `smartmoving_api_docs/` rank below both.

*Last verified against the live warehouse: 2026-08-08.*

---

## 1. The four mechanisms

Most of the confusion in this project came from treating "the API" as one thing. It
is two things with wildly different costs, and conflating them is what kept the
warehouse at 15% coverage for a month.

| Mechanism | Cost | Coverage | Latency | Its job |
|---|---|---|---|---|
| **Webhooks** | Zero | Everything that changes | Seconds | **Latency.** Status ledger, plus triggers for the detail call. |
| **Scheduled reports** (email) | Zero | The whole business | Hours | **Coverage and depth.** The backbone. |
| **API sweep** — `/api/customers` | ~1 call per **200 customers** | Everything with a job in the service-date window | Minutes | **Identity.** GUID ↔ quote crosswalk, status, customer contact. |
| **API detail** — `/api/opportunities/{id}` | **1 call per opportunity** | Only what you name | Minutes | **Depth on the few.** Charges, payments, addresses, contacts, surveys. |

**The rule that follows:** the sweep is cheap enough to run in every scheduled pass.
The detail call must always be *triggered by something*, never scheduled broadly. A
scheduled detail call over a wide window is the one design mistake that exhausts the
quota.

### Why the sweep is so cheap

`GET /api/customers?IncludeOpportunityInfo=true` returns, for every customer it
matches, all of their opportunities **including the opportunity GUID and the quote
number**. Measured on live data 2026-08-08: **685/685 and 514/514 rows carried both.**

A 730-day sweep cost **16 calls on `ld` and 51 on `local`** — 67 calls for two years
of both instances. The same coverage via detail calls would have been ~13,000.

That single measurement is why this contract exists in its current form. Widening the
sweep from `[-7,+30]` to `[-180,+60]` moved report resolution from **10.2% to 41.0%**
and grew `core.opportunities` from 2,169 to 14,014 — for 67 calls.

---

## 2. The crosswalk, and why it matters

Reports identify an opportunity by its **`Quote #`**. Webhooks identify it by its
**GUID**. They are different keys, and nothing joins them for free.

The sweep is the bridge: it returns both, so `marts.int_opportunity_quote_crosswalk`
can map `(source_instance_id, quote_number) → external_opportunity_id`.

**Without a wide crosswalk, reports cannot attach to anything.** This is the single
most important causal chain in the design:

```
wide, cheap sweep  →  big crosswalk  →  reports attach  →  opportunities are enriched
```

If report resolution is falling, the crosswalk is the thing to look at first.

⚠️ **The composite key is not optional.** Quote numbers are unique only *within* an
instance. A naked quote number will silently attach a `local` quote to an `ld`
opportunity — no error, just wrong numbers forever.

---

## 3. What each mechanism cannot do

Read this section before proposing any change to extraction. Every line is a measured
limit, not a guess.

**The API as a whole**
- **There is no `modifiedSince` filter on any endpoint.** You cannot ask "what changed
  since yesterday". This is why a hash-diff sweep exists at all.
- **~120 calls/minute** trips `429 Rate limit is exceeded`, confirmed by measurement.
  The `pace` throttle exists for this. **429 responses still consume quota.**
- Every page counts as a call. `PageSize` is capped at 200 by the server.
- **`Include*` flags are free** — they do not change the quota cost of a call. Always
  request all of them.

**The sweep specifically**
- **It is anchored on the job's service date.** Verified 2026-08-08: all 14,572
  opportunities the sweep returned have at least one job; none had zero. An
  opportunity that never got a job scheduled is **structurally unreachable** by the
  sweep, no matter how wide the window. Bad leads resolve at only **5.6%** for exactly
  this reason.
- **It is blind to money and to `leadStatus`.** It returns status, quote number, and
  customer — never a charge, payment or estimate. This is why a change to a quote
  cannot be detected by the sweep and needs either a report or a trigger.
- Bonus behaviour worth knowing: the filter applies to the **customer**, so a matching
  customer brings *all* their opportunities, including ones outside the window. A
  `[-90,+30]` request on `ld` returned service dates spanning 2025-08 to 2026-09.

**Webhooks**
- **There is no lead-created webhook.** The 17 available events start at
  `opportunity-created`. **Leads are polling-only, always.** Any document claiming
  leads are webhook-fed is wrong.
- SmartMoving retains only **7 days** of webhook history, so an outage longer than
  that is unrecoverable from the vendor side.
- Payloads are **ID-only**. A webhook tells you *that* something changed, never *what*.
- They drop, arrive out of order, and replay. **Webhooks provide freshness; polling
  provides correctness.** Every webhook-fed entity must also have a reconciling poll.

**Reports**
- Delivered as a **download link to Azure Blob Storage**, never as an attachment. The
  subject line is generic for every report type; the type comes from the filename.
- The report's `Status` string **cannot be mapped to the platform status integer.**
  Measured: 185 rows read `Closed` while the API said `status_code = 4` (Booked), and
  `Cancelled service no longer needed` maps to both `4` and `20`. The string carries
  the lost/cancelled *subcategory*, which the integer cannot express; the integer is
  authoritative for the outcome. Keep them in separate columns. See
  [`status_model.md`](status_model.md).
- Report columns suffixed `at Utc` are **not UTC** — they render in the CRM instance's
  configured timezone (`dim_instance.crm_timezone`).

---

## 4. The flow, entity by entity

| # | What happens | Mechanism | Lands in |
|---|---|---|---|
| 1 | **A new lead arrives** | Polling only — no webhook exists | `raw_smartmoving.leads` → `core.leads` |
| 2 | **A lead becomes an opportunity** | `opportunity-created` webhook (ID only), then the sweep supplies the quote number | `webhook_events`, `customers_service_window` |
| 3 | **Its status changes** | `opportunity-status-changed` webhook → status ledger. **No API call.** | `webhook_events` → `int_opportunity_observations` |
| 4 | **Money, addresses, salesperson** | Scheduled reports, 6×/day, zero quota | `raw_smartmoving.report_*` |
| 5 | **A job closes** | `job-closed` / `job-finalized` / `payment-made` → **one** detail call | `opportunities_enriched` |
| 6 | **Historical backfill** | `--sweep-only` over a wide window; All Time report exports | crosswalk + `report_*` |

Leads and opportunities are **separate, independent records**. There is no
lead→opportunity map, and `/api/leads` does not return an opportunity id. Note that
the *lost-leads* report keys on `Quote #`, so despite its name it enriches
opportunities, not leads.

---

## 5. Enrichment triggers — the allowlist

The detail call costs one call per opportunity. What may trigger it is a closed list.

| Event | Volume observed | Trigger a detail call? |
|---|---|---|
| `job-closed` | 525 | ✅ **Yes** — financials are final and will not move again |
| `job-finalized` | 230 | ✅ **Yes** |
| `payment-made` | 670 | ✅ **Yes** |
| `opportunity-status-changed` | 3,557 | ❌ Status ledger only |
| `opportunity-created` | 944 | ❌ The sweep will pick it up |
| `opportunity-changed` | **31,085 (72% of all events)** | ❌ **Never** |
| `follow-up-*`, `customer-*` | ~6,400 | ❌ Out of scope |

⚠️ **`opportunity-changed` is the one line item that can exhaust the quota.** It fires
on every UI edit — 422 events in 25 minutes has been observed. Enriching on it would
cost more calls per day than the allowlist costs per month.

Spending quota at `job-closed` is spending it at the moment the data stops changing,
which is the best possible time to pay for it.

---

## 6. Schedule

**One table. This is the only place cron times are defined.** Times are
`America/Los_Angeles`.

| Workflow | When | What it does |
|---|---|---|
| `report_ingest` | IMAP trigger | Lands whatever report email arrives |
| SmartMoving report sends | **07:00, 11:00, 13:00, 15:00, 18:00, 21:00** | Configured in the SmartMoving UI, not in n8n |
| `opps_sweep` | 06:30, 10:30, 13:30, 16:30, 20:30 | Sweep `[-180, +60]`, both instances |
| `leads_poll` | aligned with the sweep | Leads have no webhook; polling is their only path |
| `dbt_build_reports` | 07:00 daily | `dbt seed` + `dbt build`, under `flock` |
| `Enrichment_worker` | every 5 min | Drains the trigger allowlist only |
| `nightly_reconciliation` | 02:00 | `--refresh-stale-hours 336` |
| `weekly_dims` | weekly | Dimensions |

**Sweep window is `[-180, +60]` everywhere.** One window for every run, deliberately.
Earlier the codebase used two different narrow windows for `opps_sweep` and the
nightly reconciliation, and they thrashed each other's presence set into false
deletions.

<!-- SWEEP_WINDOW: -180,+60 -->
<!-- The line above is parsed by scripts/check_sync_contract.py, which fails the
     build if pipeline/run.py and source.py disagree with it. Change it here first,
     then the code - never the other way round. -->

### Report retention, in one line

<!-- REPORT_RETENTION_DAYS: 10 -->
Keep every generation for 10 days, then one per day. Detail in section 9.

---

## 7. Quota

**125,000 calls/month per instance**, two instances, so 250,000 total. Each instance
carries its own budget and ledger; every call is logged to
`scripts/api_call_log.jsonl`.

| Line | Per run | Runs/day | Calls/month, both instances |
|---|---|---|---|
| Sweep `[-180,+60]` | ~6 `ld` + ~22 `local` | 6 | ~5,000 |
| Leads poll | ~2 `ld` + ~12 `local` | 6 | ~2,500 |
| Triggered enrichment (allowlist) | 1 per event | — | ~1,400 |
| Staleness TTL backstop | — | — | ~6,000 |
| Dimensions | ~13 | weekly | ~100 |
| Reports | **0** | 6 | **0** |
| Webhooks | **0** | — | **0** |
| **Total** | | | **~15,000 of 250,000 (6%)** |

⚠️ **`local` also carries a legacy API consumer at ~45% of its own quota.** That is
outside this pipeline and outside this ledger. Retiring it is the single largest
quota win available.

**Guardrails:** a per-run `--budget`, a daily ledger gate that pauses the enrichment
worker past its cap, and a `pace` throttle for the ~120/min limit. Cheap sweeps and
leads polls are never paused — only the detail call is.

---

## 8. Freshness targets

Published, monitored obligations. Every `serving` view carries `synced_at` so
consumers can see the truth rather than trust the target.

| Entity | Mechanism | Target |
|---|---|---|
| Opportunity **status** | Webhook | < 15 min |
| Opportunity **money / detail** | Reports, 6×/day | < 4 h |
| Leads | Polling, 6×/day | < 4 h |
| Jobs | Sweep + `job-closed` trigger | < 4 h |
| Dimensions | Weekly | < 7 d |

---

## 9. Retention

Six report generations a day × ~4,800 rows is ~29,000 rows/day, ~10 million a year,
from Lead Status alone. The droplet is at **90% disk**, so this is not theoretical.

**Policy: keep every generation for 10 days, then one generation per day.** dbt
already collapses to the newest observation per row, so pruning older intra-day
generations loses nothing analytical — only the ability to replay a specific
mid-morning snapshot from more than ten days ago.

Implemented in `sql/34_report_retention.sql`, run from the daily dbt workflow.

---

## 10. Where this is measured

Coverage as of 2026-08-08, after widening the sweep:

| | Before | After | Cost |
|---|---|---|---|
| Report resolution | 10.2% | **41.0%** | 67 calls |
| Crosswalk entries | 1,199 | **13,157** | |
| `core.opportunities` | 2,169 | **14,014** | |
| …with a customer | 708 | **13,157** | |
| …with money | 691 | **2,679** | |
| Webhook-only shells | 1,461 | **857** | |
| `core.leads` | 48 | **2,708** | 14 calls |

**Open question, deliberately not papered over:** 2,458 report rows remain unmatched
without a clean explanation — they have service dates inside the swept span and
non-lead statuses. The job-anchoring limit in §3 explains bad leads (5.6% match) and
some lost opportunities, but not all of it. Worth one focused investigation. It does
not block anything: those rows are surfaced in `marts.mart_unmatched_report_rows`,
never dropped.
