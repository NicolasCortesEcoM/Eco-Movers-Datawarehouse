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
| **API quote resolver** — `/api/opportunities/quote/{n}` | **1 call per quote** | Any quote a report names, *including opportunities that have no job* | Minutes | **Identity the sweep structurally cannot reach.** See §2a. |

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

### 2a. The quote resolver, and why the sweep alone was never going to be enough

The sweep is anchored on a job's service date (§3), so an opportunity that never got
a job scheduled cannot enter the crosswalk at any window width. That is the endpoint's
shape, not a tuning problem — and it is not a small residue. Measured 2026-09-07:
**9,196 of 15,437 Lead Status quotes (59.6%) had no GUID**, and the gap is biased
toward the outcomes that never produce a job:

| Report status | Resolved | Unresolved |
|---|---:|---:|
| Booked / Closed / Completed | 3,135 | 2,516 |
| Lost | 2,291 | 4,323 |
| Bad lead | 81 | 1,463 |

`core.opportunities` therefore reported **50.2% conversion against a true 36.6%** —
overstated by 13.6 points, structurally, every month.

`GET /api/opportunities/quote/{n}` closes it. Verified live 2026-09-07 against 8
unresolved quotes including zero-job and null-service-date ones, then against a
50-quote batch: **50 of 50 resolved, zero 404s.** It is not Premium, it takes the same
`Include*` flags, and it returns the same payload shape as the detail call — so it
lands in the same raw table and the crosswalk picks it up with no new dbt model.

⚠️ **It costs one call per quote, the same as the detail call.** It is therefore a
*budgeted drain*, never a sweep: `--job quote_backfill` selects unresolved quotes
newest first, takes only as many as `--budget` allows, and records every attempt in
`raw_smartmoving.quote_resolution_attempts` so a quote that genuinely does not exist
is not paid for again every night.

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
  this reason. **This is now recoverable** — not by widening the window, which cannot
  help, but by the quote resolver in §2a.
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

⚠️ **A LEAD AND AN OPPORTUNITY ARE THE SAME RECORD.** This section said the opposite
for months — *"separate, independent records… `/api/leads` does not return an
opportunity id"* — and it was wrong. The lead's own `id` **is** the opportunity GUID.
Evidence, 2026-09-09: 23,717 of 36,895 lead ids are byte-identical to an existing
`core.opportunities.external_opportunity_id`, and six lead ids that were *not* in that
table were put to `GET /api/opportunities/{id}` — all six returned 200, echoed the same
id, and carried a `quoteNumber`.

What the belief cost: **13,196 opportunities missing from `core`**, overwhelmingly bad
leads and leads still in progress. Every API opportunity path reaches an opportunity
**through its jobs** (the sweep window is a service-date window, and service dates live
on jobs), so a lead that never converted was invisible to all of them — 98.4% of the
opportunities present in `core` have a job, against 5.5% of the absent ones. They were
missing from the conversion *denominator*, so every rate in the sales layer read high.

`/api/leads` is now an arm of `int_opportunity_observations`, joined on the identifier
SmartMoving itself issues. No fuzzy matching is involved and none is needed.

Note that the *lost-leads* report keys on `Quote #`, so despite its name it enriches
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
| `report_ingest` | **every 2 min** (`*/2 * * * *`, Gmail sweep) | Lands **one** report email per execution, verifies its row count, trashes the email, then rebuilds dbt **only if no other report is still queued** - so a burst of six reports costs one rebuild, not six. A run that finds nothing costs ~0.7 s; one that lands a report without rebuilding, ~15 s. The IMAP trigger is disabled: it had not fired a single execution in weeks, and it is unbounded - it delivers however many emails are waiting, which is what exhausted the heap on 2026-09-08. One report per run bounds memory to a single xlsx and removes every paired-item lookup from the graph. |
| SmartMoving native report sends | **03:00, 11:00, 13:00, 15:00, 18:00, 21:00** | Configured in the SmartMoving UI. Five report types can send themselves: Lead Status, Booked, Lost Leads, Cancellations and Payments. **All Jobs is excluded because SmartMoving does not allow it to be scheduled.** |
| `opps_sweep` | 06:30, 10:30, 13:30, 16:30, 20:30 | Sweep `[-180, +60]`, both instances |
| `leads_poll` | aligned with the sweep | Leads have no webhook; polling is their only path |
| `dbt_build_reports` | **03:30 daily** (`30 3 * * *`) | `dbt seed` + `dbt build`, under `flock`. It does **not** prune - see the row below |
| `report_retention` | **04:10 daily** (cron on the droplet, not n8n) | Replays `sql/34_report_retention.sql`. This contract claimed for months that `dbt_build_reports` did it; the workflow never has, so until 2026-09-08 pruning only happened on manual deploys |
| `Enrichment_worker` | every 5 min | Drains the trigger allowlist only |
| `nightly_reconciliation` | 02:00 | `--refresh-stale-hours 336` |
| `weekly_dims` | weekly | Dimensions |
| `pipeline_heartbeat` | **every 30 min at :05/:35** (cron on the droplet, NOT n8n) | Asks when each mechanism last SUCCEEDED and alerts on silence. It is outside n8n on purpose: every other alert here fires when a node throws, which cannot see a job that never ran. See §11. |
| `quote_backfill` | **once per report burst**, inside `report_ingest`, at `--budget 300` per instance | Resolves Lead Status quotes with no GUID, newest first. Runs only when `Inbox Drained?` is true — i.e. the last execution of a burst — and **before** `Rebuild dbt now`, so one build publishes the reports and the newly resolved quotes together. Holds a non-blocking `flock`, so overlapping executions skip rather than spend the budget twice, and is `onError: continue` because the reports are already row-count verified by then and an enrichment failure must not block publishing them. See §2a. |
| `report_bot_all_jobs` | **02:50** (full year) and **10:00, 13:00, 16:00, 20:00** (last 90 days) | Runs the Playwright browser bot on the droplet. The bot logs in, opens All Jobs, sets the date range and clicks **Run Report**, causing SmartMoving to email the XLSX. SmartMoving cannot schedule this report itself. The bot uses zero API quota and never downloads, parses or loads the file; `report_ingest` owns those steps. |

### The six reports, and what each one uniquely carries

All six land through `report_ingest` at **zero API quota**. Nothing else in the
warehouse carries the columns in the right-hand column.

| Report | Key | Uniquely provides |
|---|---|---|
| Lead Status | `Quote #` | The denominator - every lead regardless of outcome. `Received at` (the lead date, on 100% of rows). |
| Booked Opportunities | `Quote #` | `Invoiced Amount` - **the only realised-revenue column in the warehouse**. |
| Lost Leads | `Quote #` | `Lost Date`, `Reason`, `Time to First Contact`. |
| All Jobs | `Job Id` | The itemised realised-revenue breakdown (vendor columns are misleadingly named `Actual * Cost`), crew and truck counts, hourly rates and pricing method. Requested through browser control by `report_bot` because SmartMoving cannot schedule it. |
| **Cancellations** | `Quote #` | **`Cancelled Date`** - the warehouse had no cancellation date at all before this. Plus `Amount` (revenue lost) and `Reason`. |
| **Payments** | hash of the row | `Date`, `Amount`, `Payment Category`, and links to **Quote, Job OR Storage Account**. |

⚠️ **A payment can attach to a storage account that has no quote number.** Storage
accounts are a third top-level entity alongside opportunities and jobs. When the
payments model is written it needs a nullable link to each of the three plus a target
discriminator - forcing every payment under an opportunity id would silently drop
every storage payment.

⚠️ **`local` reports were rejected for twelve days** (2026-08-14 to 08-25) because they
arrive at `local.reporting@ecomovers.com` and the `ecomovers.com` domain was not in
the alias map. Fixed 2026-08-25.

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
| Quote backfill (drain) | 1 per unresolved quote | see §2a | **~9,200 once**, then ~1,500–3,000 |
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

## 9a. Silence is a failure mode, and it had no detector

Every alerting path in this project lives INSIDE an n8n execution: a node throws and
`errorWorkflow` catches it. That covers a job that runs and fails. It covers nothing
when the job does not run at all - an execution killed by the OOM reaper, a container
restart mid-run, a schedule trigger that never fires, or a workflow wedged in a state
where it neither errors nor progresses.

**The last one happened.** `report_ingest` collected nothing between 2026-09-07 18:10 PT
and a container restart around 03:00 the next morning: nine hours, 39 unread emails in
the mailbox, zero errors logged, zero alerts raised. It then recovered on its own. The
stall was found by hand while auditing something else.

**Then it happened again, and the second time it did not recover.** From 2026-09-08
11:10 PT the workflow ran out of memory on every execution for 24 hours. The mechanism
is worth recording because it was a loop, not a fault:

1. The Gmail sweep collected **every** report email still in the inbox - `newer_than:2d`,
   roughly 60 emails and 200,000 rows - and processed them in ONE execution.
2. Rows were landed one INSERT per row, and n8n retains the input and output of every
   node for the life of the execution, so the reports were held in memory five or six
   times over. Executions ran 20 to 30 minutes; then the heap gave out.
3. Cleanup - trashing the processed emails - sat at the very END of the graph, behind
   the dbt rebuild. A crash therefore left every email in the inbox, so the next sweep
   picked up the same batch plus the new arrivals, and crashed harder.

Nothing alerted, because a process killed for memory throws nothing. Fixed 2026-09-09
by bounding the batch to one report per execution, landing each report with a single
set-based INSERT, and moving the cleanup to immediately after the row-count check -
the point at which the email is provably consumed - so a downstream failure can no
longer feed the loop.

The "Paired item data for item from node 'Download Report File' is unavailable" error
seen while debugging was a SYMPTOM, not the cause: when n8n recovers a crashed run it
replaces every node's output with a stub carrying no `pairedItem`, so re-running one
fails on the first `$('...').item` lookup. Those lookups are now `.first()`, which is
unambiguous because there is exactly one report per execution.

`scripts/pipeline_heartbeat.py` runs from cron on the droplet and asks the opposite
question - not "did anything fail?" but "when did each mechanism last succeed?" - for
reports, webhooks, dlt extraction and the dbt build. Findings are recorded in
`monitoring.pipeline_heartbeat` on EVERY run, not only bad ones, so a heartbeat table
with no recent heartbeat is itself the signal that the monitor stopped.

Its thresholds are deliberately looser than the freshness targets in §8 and are not a
restatement of them: a target describes what consumers are promised, an alert threshold
has to sit beyond normal variation or it becomes noise nobody reads.

⚠️ **Slack delivery needs one value.** Set `HEARTBEAT_SLACK_WEBHOOK` in the droplet
`.env` to an incoming-webhook URL. Without it the check still runs, still records, and
still exits non-zero - but the finding only reaches cron's local mail.

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
