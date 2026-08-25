# Architecture — how data actually moves

**Visual map:** <https://claude.ai/code/artifact/56f0fce3-9604-497f-a5e2-70dd3e402ff4>

The map is the thing to open first. It traces every source to every table, shows what
a webhook and a report each set in motion, and carries the schedule as a clock. This
file is its text counterpart, for grepping and for review in a diff.

> **[`crm_sync_contract.md`](crm_sync_contract.md) is the authority on cadence, quota
> and which mechanism feeds each entity.** Nothing here restates its numbers.
> `scripts/check_sync_contract.py` fails the build if anything does.

---

## The one idea everything rests on

SmartMoving can be read four ways, and they are not interchangeable.

| Mechanism | Cost | Coverage | Latency | Its job |
|---|---|---|---|---|
| **Webhooks** | Zero | Everything that changes | Seconds | **Latency.** Says *that* something happened, rarely *what*. |
| **Scheduled reports** | Zero | The whole universe | Hours | **Coverage and depth.** The backbone. |
| **API sweep** (`/api/customers`) | ~1 call / 200 customers | The service-date window | Minutes | **Identity.** The GUID-to-quote crosswalk. |
| **API detail** (`/api/opportunities/{id}`) | 1 call **per opportunity** | Only what you ask for | Minutes | **Depth on the few.** Charges, payments, addresses. |

**The API is two mechanisms, not one.** The sweep is nearly free and belongs in every
run; the detail call is expensive and must be triggered, never scheduled broadly.

Measured 2026-08-25 across the whole call log: **4,821 of 4,960 calls (97%) were
detail calls.** The sweep has cost 97 calls in total, ever.

---

## The five stages

```
SmartMoving (ld + local)          9 CSV seeds in the repo
        |                                  |
        +-- webhooks -----+                |
        +-- report email -+                |
        +-- API sweep ----+                |
        +-- API detail ---+                |
                          v                v
               raw_smartmoving         (dbt seed)
               43 tables, 276 MB           |
               payload verbatim            |
                          |                |
                          v                v
                       staging  <----------+
               15 stg_* views + 9 dim_* tables
               renamed, typed, money -> numeric
                          |
                          v
               marts (int_* observation layer)
               "source S said this about O at time T"
                          |
                          v
                        core
               opportunities, jobs, leads, agents,
               branches, lines_of_business, charges, payments
                          |
                          v
                      serving
               versioned, documented, RLS-scoped
```

**Two loaders write `raw_*`, not one.** `dlt` (via `pipeline/run.py`) lands everything
pulled from the API. **n8n writes directly by SQL** for the two paths dlt is the wrong
tool for: the webhook receiver (it must record the event and answer 200 before any
processing) and the scheduled-report landing. Both write raw payloads verbatim,
append-only. A model does not care which loader filled its source table.

**Nobody outside reads `raw_*` or `staging`.** Consumers get `serving`, plus read-only
`core` under an explicit "unstable" label — see
[`decisions/0003`](decisions/0003-hybrid-serving-plus-core-read.md).

---

## What happens when a webhook arrives

1. **n8n records it and answers 200** — `raw_smartmoving.webhook_events`. Writing
   before processing is what makes a failure recoverable rather than lost.
2. **The allowlist decides whether it is worth an API call.** Only `job-closed`,
   `job-finalized` and `payment-made` trigger a detail call — the moments the
   financials stop moving. **A status change triggers nothing**; it is recorded and
   that is all.
3. **If allowed, `Enrichment_worker` spends one call** (every 5 min) into
   `opportunities_enriched` and its child tables.
4. **dbt turns the event into an observation**, not a replacement — one row saying
   *"this source, at this moment, asserted this"*. The webhook contributes the status
   and NULL for everything else, because that is all it knows.
5. **`core.opportunities` resolves per field, not per row.** The newest value of each
   *field* wins, via the `pick_latest` macro. This is why a report can add
   `invoiced_amount` without erasing the API's `estimated_total`.
6. **Everything downstream recalculates in the same build** — `lines_of_business`,
   `agents`, the serving views. Nothing is updated by hand anywhere.

> **`opportunity-changed` must never trigger a detail call.** It is 31,085 of the
> 43,338 events captured — 72% — and fires on every UI edit. Enriching on it costs
> more calls per day than the allowlist costs per month.

## What happens when a report arrives

1. **The mailbox decides the instance** — `reporting@` is local, `ld.reporting@` is
   ld. Never guessed: a misattributed quote number does not error, it just makes the
   numbers wrong forever. The report *type* comes from the filename in the download
   link, because the subject line is generic for every report.
2. **Landed verbatim as `jsonb`**, so a renamed vendor column cannot break ingestion.
3. **Row count verified against the count stated in the email.** A mismatch throws and
   alerts. A truncated report that lands quietly is far worse than one that fails.
4. **Quote number translated to a GUID** through `int_opportunity_quote_crosswalk`,
   built from API sources only — a report never resolves against another report.
   Unresolved rows surface in `marts.mart_unmatched_report_rows`, never dropped.
5. **dbt rebuilds immediately.** The report reaches `serving` minutes after the email
   arrives; the 03:30 build is a backstop, not the only path.

---

## The dimensions (seeds)

Nine CSVs under `dbt/seeds/` hold the business knowledge no source system has: which
branch belongs to which line, which agent covers which service, which status counts
as closed.

**Version control is the reason.** History, review, revert, and tests that fail the
build rather than a report. One truth, with no dev copy drifting from prod.

> **`dbt seed` DROPS AND RECREATES these tables on every build.** A row typed straight
> into Postgres is destroyed at the next run, silently, and dbt reports success.
> Verified 2026-08-25 by inserting a row and watching it disappear: 32 rows became 31,
> the hand edit gone, `PASS=10 ERROR=0`.
>
> Every seed table now carries that warning as a Postgres `COMMENT`, so it shows up in
> psql, DBeaver, pgAdmin and Metabase — in front of whoever is holding the `UPDATE`,
> which a README is not.

**Build them so one edit propagates.** The agent roster is the worked example:

| Seed | One row per | Holds | Changing it is |
|---|---|---|---|
| `dim_agent` | person | canonical name, aliases, role, `is_sales_agent` | one cell |
| `dim_agent_assignment` | person x line x period | which services, since when | one row |

Role does not vary by line, so it lives with the person. On the assignment rows it
would be repeated once per line, and a role change would have to be applied to all of
them at once — miss one and the numbers go quietly wrong. Split, the two edits never
collide. This also made `Grant K` and `Grant Korzetz` one person instead of two, with
a single CSV row and no SQL change.

---

## Audited 2026-08-25

**Working:** report ingestion (4 types across 2 instances, with per-report row-count
verification), webhooks (87,706 events), sweep plus enrichment, dbt (219 models and
tests, 0 errors).

**Gaps, in priority order:**

1. **`local` is 84% of the business and sends one report a day** — which was rejected
   for twelve consecutive days because `ecomovers.com` was not in the alias map.
   Fixed 2026-08-25. Everything `local` in the warehouse today was forwarded by hand.
2. **All Jobs is scheduled on neither instance.** Same consequence.
3. **`serving.opportunities_v1` and `serving.jobs_v1` are not published** — the stated
   Phase 1 deliverable.
4. **service_date is 88%, and that is the ceiling from free sources.** The missing
   1,815 are exactly the 1,815 with no quote number, so no report can reach them and
   they have no job to inherit from. Recovering them costs one detail call each.
   Deliberately not spent — see the contract.

**Removed or fixed in this audit:** `report_lost_leads` connected (13 MB landing daily
that nothing read; it now supplies loss reason and time-to-first-contact to 2,345
opportunities); 4 dead staging models deleted; the daily build's schedule reconciled
(it was written four different ways, none of them the actual `30 3 * * *`); seed
tables given their in-database warning; roughly 5 false alerts a day silenced.
