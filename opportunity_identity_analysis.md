# Opportunity identity: the GUID, the quote number, and which one the warehouse should be keyed on

**Status: Option C adopted; the Option A backfill is BUILT and proven.** Measured on
the droplet 2026-09-01, re-measured and acted on 2026-09-07. Section 10 records what
was actually done and what section 4a's premise looks like once tested at scale.

---

## 1. The problem this is trying to solve

`core.opportunities` is keyed on `(source_instance_id, external_opportunity_id)` -
the SmartMoving GUID. Every scheduled report except All Jobs keys on the
human-readable **Quote #**. `int_opportunity_quote_crosswalk` bridges the two.

The bridge is built **from API sources only**, deliberately. That is the defect:

| Source | Resolves to a GUID |
|---|---:|
| Lead Status report, `ld` | 1,184 of 1,950 quotes - **60.7%** |
| Lead Status report, `local` | 4,852 of 13,159 quotes - **36.9%** |
| **All report rows** | **6,015 of 15,109 - 39.8%** |

And the gap is not random. The API sweep searches by **service date** in
`[-180, +60]`. A lead that never converted has no job, therefore no service date,
therefore the sweep never sees it, therefore it never enters the crosswalk,
therefore it is invisible to `core.opportunities`.

**The warehouse preferentially sees the leads that closed.** Measured on July 2026:

| | |
|---|---:|
| Leads in the report | 1,748 |
| Booked | 687 |
| **True conversion** | **39.3%** |
| Leads the warehouse can see | 965 (55%) |
| **Conversion the warehouse reports** | **51.8%** |

Overstated by 12.5 points, every month, structurally.

---

## 2. What the `opportunityId` is actually used for

Not academic. Six real uses, all verified in the code and the data:

| Use | Where | Could a quote number do this? |
|---|---|---|
| **Webhook attachment** | `stg_smartmoving__webhook_opportunity_status` reads `payload->>'opportunity-id'` | **No.** See section 3. |
| **The enrichment call** | `GET /api/opportunities/{id}` - the detail call, the expensive one | Yes - see section 4 |
| **Job to opportunity link** | `core.jobs.external_opportunity_id`, from the sweep and the enriched payload | Partly - All Jobs' `Job Number` is `<quote>-<seq>`, a second independent path |
| **Payments link** | `GET /api/payments/opportunities/{id}`; `core.opportunity_payments` | Yes, via the same map |
| **Deletion markers** | `raw_smartmoving.opportunity_deletions` keys on the GUID | Yes, via the same map |
| **The CRM deep link** | `app.smartmoving.com/opportunities/<GUID>/estimate` | **No.** See section 6. |

---

## 3. What breaks with webhooks - the strongest argument for keeping the GUID

**Webhooks carry the GUID and nothing else.** Every payload key that exists, across
103,583 real events:

```
event-type          103,583
opportunity-id      101,250
opportunity-status   83,848
followup-id          13,514
job-id                2,590
customer-id           2,197
payment-id            1,432
storage-account-id      136
```

There is **no quote number in any webhook payload, ever.** So if the warehouse were
keyed on the quote number alone, a webhook would arrive addressed to a row the
warehouse could not name.

How bad is that today? Of 3,347 distinct GUIDs seen in webhooks, only **1,433
(42.8%)** can currently be resolved to a quote number.

**But this is self-healing, and that changes the conclusion.** The enrichment
worker's response to a webhook is a detail call, and **that call returns the quote
number**. So an unknown GUID is not a dead end - it is one call away from being
mapped, and it is a call the contract already pays for. The mapping fills itself in
the normal course of operation.

The real loss is narrower than it first looks: **a status webhook for an opportunity
that is not on the enrichment allowlist would sit unattached until something else
resolves it.** That is a freshness cost on a subset of events, not a loss of data.

---

## 4. Can the GUID be enriched by another API call? - Yes, and this is the finding that reframes the whole question

The user asked about `GET /api/leads`. Two things came out of checking it, one of
them a correction to what this repo currently says.

### 4a. `/api/opportunities/quote/{quoteNumber}` exists

It is **not** premium, and it is not mentioned anywhere in this repo's own notes.
Probed live against `ld` quote 10000 on 2026-09-01:

```json
{ "id": "2c9415ac-19ca-4489-b267-b2ff015b8045",
  "quoteNumber": 10000,
  "status": 30, "leadStatus": "Tentative Booking",
  "serviceDate": 20250702, "createdAtUtc": "2025-06-17T21:05:12+00:00" }
```

**Identical response shape to `/api/opportunities/{id}`, same `Include*` flags.** The
quote number is a first-class API key, not merely a report label.

This means the crosswalk gap is closable **without changing the identity model at
all**: one call per unresolved quote.

| | |
|---|---:|
| Quotes with no GUID today | **9,073** (766 `ld`, 8,307 `local`) |
| One-time backfill cost | 9,073 calls |
| Monthly quota | 250,000 (currently using ~15,000 = 6%) |
| Ongoing cost | ~50-100 new unresolved quotes/day |

**That backfill is affordable.** It is 3.6% of one month's quota, once.

### 4b. Correction: `/api/leads` DOES return the opportunity GUID

`core/opportunities.sql` states, in a comment that shapes the whole design:

> *"There is no join to core.leads and no lead->opportunity map. `/api/leads` does
> not return an opportunityId."*

**That is wrong.** The lead's `id` **is** the opportunity GUID. Measured against
3,241 polled leads:

| The lead's `id` also appears as an opportunity id in... | Rows |
|---|---:|
| `customers_service_window__opportunities` | 938 |
| `opportunities_enriched` | 508 |
| `webhook_events.payload->>'opportunity-id'` | 1,112 distinct |

GUIDs do not collide across namespaces by chance. They are the same identifier.

**Why it does not solve the problem on its own:** `/api/leads` returns the GUID but
**no quote number** (confirmed against the raw table's 36 columns - there is no quote
column). And the reports carry the quote but no GUID. So the two feeds are disjoint
populations that cannot be joined to each other, only to a third thing. `/api/leads`
is a *second GUID source*, not a bridge.

It is still worth wiring up: it is already polled, already includes `IncludeBad` and
`IncludeLost`, and it reaches leads the service-date sweep structurally cannot.

---

## 5. Quote number as the key: what is gained, what is lost

### Gained

| | |
|---|---|
| **Completeness** | Present on **100%** of rows in all four sources: Lead Status (332,123 rows), Booked (115,181), API sweep (13,216), API enriched (2,555). |
| **Zero quota to create a row** | A report row alone becomes an opportunity. The conversion denominator stops depending on the paid channel. |
| **Every report attaches directly** | Booked, Lost Leads, Cancellations, Payments, Outstanding Balances - no bridge, no bridge to maintain. |
| **The bias disappears** | Conversion is measured on the population the CRM itself reports, not on the subset the sweep happened to touch. |
| **Human-legible** | A key you can read out over the phone and type into the CRM search box. A GUID is neither. |

### Lost

| | |
|---|---|
| **Direct webhook attachment** | Webhooks name the GUID only. Mitigated but not eliminated - see section 3. |
| **The deep link, for rows that have no GUID** | See section 6. |
| **A vendor-guaranteed identifier** | The GUID is opaque and immutable by construction. A quote number is a business-facing counter - it is *observed* not to collide, which is not the same as *guaranteed* not to. |
| **Instance-global uniqueness** | Quote numbers are unique only **within** an instance (`ld` uses 5 digits, `local` 6 - today). The key must be `(entity_id, source_instance_id, quote_number)`. It is never safe naked. This is already CLAUDE.md rule 7. |

**Measured collisions: zero.** `ld` 2,345 distinct of 2,345 rows; `local` 11,135 of
11,135.

### The unknown worth stating plainly

**Nobody has established that SmartMoving never reassigns or edits a quote number.**
The GUID is safe to assume immutable. The quote number is not, and this analysis
cannot prove it. That risk is detectable - a uniqueness test on the crosswalk, and an
alert when an `(instance, quote)` pair ever points at a second GUID - but it is a
risk the GUID does not carry.

---

## 6. How important is the GUID on every row? - It is a real requirement, not a nice-to-have

```
https://app.smartmoving.com/opportunities/5773fe04-.../estimate
https://app.smartmoving.com/opportunities/5773fe04-.../accounting
```

The CRM's own URLs are built on the GUID. Any warehouse row a human will click
through to SmartMoving needs it. That covers most of what is being built - a
dashboard row a manager wants to open, an exception report, an unmatched-record
queue.

**So the GUID must be on every row that a person will act on.** That is a different
statement from "the GUID must be the primary key", and confusing the two is what
produced the current situation.

A row that is only ever counted - a lost lead in a conversion denominator - does not
need a link. A row somebody will open does. The GUID belongs on the table; it just
does not have to be what identifies the row.

---

## 7. Three options, honestly compared

### Option A - keep the GUID as the key, backfill the crosswalk

Call `/api/opportunities/quote/{n}` for the 9,073 unresolved quotes, then for new
ones daily.

- **Achieves the same completeness as Option B.** This is the point that must not be
  glossed over: the bias is fixable without touching the identity model.
- Nothing changes in `core`, `staging`, the webhook path or the deep links.
- Costs 9,073 calls once, ~50-100/day after.
- **The weakness is structural, not numeric:** the free, complete source stays gated
  behind the paid, partial one. If the enrichment worker is paused, or a quota gate
  trips, or the API is down for a day, the conversion denominator degrades - even
  though the report that carries it arrived perfectly well by email. It also means
  every future report-only source (cancellations, payments, storage) inherits the
  same dependency.

### Option B - quote number becomes the identity, GUID becomes an attribute

`opportunity_key = entity_id : source_instance_id : quote_number`, with
`external_opportunity_id` carried as a resolved column.

- Reports attach with no bridge. A report-only lead is a first-class row at zero
  quota.
- The GUID is still populated for every row any API source has touched, so deep links
  work where they matter.
- Webhooks attach via a GUID-to-quote map that the enrichment call fills for free.
- **Cost:** this is the largest change made to the warehouse so far. It touches
  `int_opportunity_observations`, every staging model, `core.opportunities`,
  `core.jobs`, `core.opportunity_charges`, `core.opportunity_payments`, the serving
  views, and every test keyed on `opportunity_key`.
- **Risk:** the quote-number immutability assumption in section 5.

### Option C - do both, in that order

Run the Option A backfill **now** (it is a script and a quota decision, not a
migration), which removes the KPI bias this week. Then decide Option B calmly, with
the numbers already correct, and with a crosswalk that is 100% populated - which is
precisely the condition that makes the Option B migration verifiable, because every
row's old key and new key would both be known.

---

## 8. Recommendation

**Option C.**

The reasoning is that A and B are not really competing designs - A is the
prerequisite that makes B safe. Migrating identity while 60% of the mapping is
missing means migrating without being able to check that the new key and the old key
describe the same row. Backfilling first turns the migration from a leap into a
comparison.

And it decouples two things that do not have to happen together: **the KPI numbers
are wrong today**, and that is fixable in days with a backfill script. **The identity
model is architecturally wrong**, and that deserves a proper migration rather than
being rushed because the numbers are wrong.

---

## 9. Open questions to settle before the migration plan is written

1. **Is a quote number immutable in SmartMoving?** Can it be edited, reassigned, or
   reused after a delete? The vendor should be asked; the data cannot answer it.
2. **Does a quote number exist before an opportunity does?** If a lead can be lost
   before a quote is issued, the quote key has a hole the GUID does not.
3. **Do storage accounts have quote numbers?** `storage-accounts.xlsx` keys on
   `Account #`. If they never carry a quote, the payments model needs its
   discriminator regardless of which key wins.
4. **What is the legacy API consumer on `local` doing?** It burns ~45% of that
   instance's quota, outside this ledger. Retiring it funds the backfill several
   times over.
5. **Should `/api/leads` be wired into `int_opportunity_observations`?** It is a free
   GUID source for non-converted leads and is currently polled and discarded. The
   comment saying it carries no opportunity id is wrong (section 4b) and should be
   corrected in `core/opportunities.sql` either way.

---

## 10. Outcome — 2026-09-07

**Option C was adopted and its first half shipped.**

### Section 4a's premise held under test

The 2026-09-01 probe was a single quote (`ld` 10000) that had a service date, so it
proved nothing about the population that actually matters — opportunities the
service-date sweep cannot reach. Re-probed against 8 deliberately *unresolved* quotes,
including zero-job and null-service-date ones:

```
ld    13138  -> dc65c0ef…  status=50 jobs=0  (Bad lead duplicate lead)
ld    13123  -> d85310d7…  status=30 jobs=0  (Lost, moving themselves)
local 128167 -> 868c8a1d…  serviceDate=None jobs=0
```

8 of 8. Then a 50-quote batch through the real pipeline: **50 of 50 resolved, zero
404s**, all 50 into the crosswalk, all 50 into `core.opportunities` — each carrying
sales agent, lead date and estimated amount, the three fields the sales KPIs need and
that none of them had before.

### What was built

`pipeline/run.py --job quote_backfill`, plus a `quotes=` arm on `smartmoving_source`.
It selects unresolved Lead Status quotes from the warehouse newest first, capped by
`--budget`, resolves them through `/api/opportunities/quote/{n}`, and lands the payload
in the **existing** `raw_smartmoving.opportunities_enriched`. **Zero new dbt models** —
the crosswalk is built from that table, so it picks them up on its own. Attempts are
recorded in `raw_smartmoving.quote_resolution_attempts` so a dead quote is not paid for
twice. Mechanism and cost are in `crm_sync_contract.md` §2a.

### The finding that settles the Option B question, for now

Section 7 assumed Option B's cost was the model rewrite. Measurement found a second
cost that section 7 does not mention and that argues against doing B first:

**Every one of the 2,032 quote-less rows in `core.opportunities` is webhook-only** — a
GUID and a status integer, single source, no name, no quote, no agent, no date. They
are the same opportunities as the unresolved report rows, and with no shared key
**they cannot be merged in SQL**. So making the quote a first-class key without
backfilling first does not just add rows, it adds up to 2,032 *duplicate* rows over
precisely the population being fixed.

The backfill dissolves them instead of merging them: the 50-quote trial took the shell
count from 2,032 to 1,990. That is the mechanism working, and it is the strongest
argument for A-before-B that this document did not have on 2026-09-01.

### Also corrected

Open question 5 is partly answered and question 1 is not: nothing here establishes
quote-number immutability, and Option B still should not be attempted until it is.

`marts.mart_unmatched_report_rows` was found to be an unreliable gauge while this was
being sized — two different Lead Status schedules write to one table, so "the latest
generation" alternates between a ~15,400-row and a ~5,200-row report. See `DATABASE.md`.

