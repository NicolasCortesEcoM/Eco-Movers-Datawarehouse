# The database, as it is built

**Read this before changing anything in the warehouse.** It is the reference for what
schemas exist, what lives in each, how they relate, and which rules are enforced where.

> **Keep it current.** Any change that adds, removes or renames a schema, a `core` /
> `marts` / `serving` object, a seed, or a key relationship must update this file in
> the same commit. A stale map is worse than none.

Last reconciled with the current dbt project and live-audit documentation:
**2026-09-08**.

Related documents, each owning something this one does not:

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how data _moves_: the four mechanisms, the flow.
- [`crm_sync_contract.md`](crm_sync_contract.md) — **the authority** on refresh cadence and API quota.
- [`serving_catalog.md`](serving_catalog.md) — the published contract for consumers.

---

## The five schemas

| Schema                              | Industry term      | Objects                  | What it holds                                                      | Who may read it           |
| ----------------------------------- | ------------------ | ------------------------ | ------------------------------------------------------------------ | ------------------------- |
| `raw_smartmoving`                   | Bronze             | 45 tables                | Source payloads exactly as received. No transformation.            | dbt only                  |
| `raw_google_ads`                    | Bronze             | 2 tables (empty until Google approves the token) | Google Ads cost per (child account, campaign, day) and the manager's account tree. Pre-created by `sql/40_raw_google_ads.sql` in dlt's shape. PK `(platform, account_id, campaign_id, date)`: `account_id` is the CHILD customer id, so the same campaign id under two accounts never collides. | dbt only |
| `staging`                           | Silver             | 9 seed tables + 15 views | Renamed, typed, lightly cleaned. **Money becomes `numeric` here.** | dbt only                  |
| `marts` (the `int_*` half)          | Silver             | 8 objects: 6 views + 2 tables | The observation layer — "source S said this about O at time T". | dbt only                  |
| `core`                              | Silver (conformed) | 8 tables                 | The canonical business entities, reconciled across sources.        | dbt + read-only apps      |
| `marts` (the `fct_*`/`mart_*` half) | Gold (internal)    | 4 objects: 3 tables + 1 view | Analytical models. May change whenever an analyst needs it.     | analysts, BI              |
| `serving`                           | Gold (contract)    | 5 tables                 | Versioned, documented, stable.                                     | other teams' applications |

The existing names are kept rather than renamed to Bronze/Silver/Gold: renaming
schemas would break every model, the RLS script, and the consumer documentation for no
functional gain. The mapping above is the translation.

---

## `core` — the canonical entities

Every one is a **table** with an `entity_id` column and an RLS policy.

Counts measured 2026-09-10.

| Table                  | Grain                                                              |   Rows | Cols |
| ---------------------- | ------------------------------------------------------------------ | -----: | ---: |
| `opportunities`        | `(source_instance_id, external_opportunity_id)`                    | 71,914 |   60 |
| `jobs`                 | `(source_instance_id, external_job_id)`                            | 63,576 |  100 |
| `lines_of_business`    | one per job                                                        | 63,576 |   12 |
| `leads`                | `(source_instance_id, external_lead_id)`                           | 36,932 |   33 |
| `opportunity_charges`  | `(instance, external_job_id, charge_kind, seq)` — **job grain**    | 10,209 |   15 |
| `payments`             | `(instance, row position in the newest Payments export)`           |  3,037 |   19 |
| `opportunity_payments` | `(instance, external_opportunity_id, seq)`                         |  2,006 |   13 |
| `agents`               | one per CRM-written salesperson name                               |     68 |    8 |
| `branches`             | `(source_instance_id, branch_name)` — **the timezone authority**   |      8 |   18 |
| `entity_access`        | `(role_name, entity_id)` — **access control, owned by `postgres`** |      — |    2 |

### WARNING: `opportunities` grew by 13,196 rows on 2026-09-09, and it was a bug fix

It was 58,678. `/api/leads` became an arm of `int_opportunity_observations` because the
lead's `id` **is** the opportunity GUID — a fact three documents in this repo denied. The
rows added are almost entirely leads that never converted, which every API opportunity
path had been blind to: those paths reach an opportunity through its **jobs**, and a lead
that never converted has none. 98.4% of the opportunities already present have a job,
against 5.5% of the ones that were missing.

**Booked did not move** (26,644 → 26,639). The whole correction is in the denominator, so
every conversion rate published before that date read high. See `AUDIT_PLAN.md` A5.

### WARNING: `payments` and `opportunity_payments` are different tables on purpose

`opportunity_payments` holds payments embedded in the API's enriched opportunity payload —
only the opportunities a detail call reached, but with a real GUID and ordinal.
`payments` is the Payments scheduled report taken whole: every payment in the report
window at zero quota, carrying the payment **date**, method, card confirmation, terminal,
and payments made against a **job** or a **storage account** rather than an opportunity.

They are **not merged, and must not be.** There is no shared payment identifier to merge
on — SmartMoving emits no payment id and the report carries no GUID — so any union would
either double count or invent a match.

`payments` is a **snapshot, not a ledger**: it is the newest export, because the report's
row key is the row's position in the file. A payment that falls out of the report window
disappears from it. Never use it as a financial system of record, and never diff two
builds of it to detect refunds.

### WARNING: `core` also holds three tables that are not ours

`workspace_tasks` (13,217), `workspace_projects` (60) and `workspace_departments` (6) are
written by a different application in the group that shares this database. They have no
`entity_id` contract with this warehouse and no dbt model owns them. **Reported, never
touched.** See section D of `AUDIT_PLAN.md`.

### WARNING: `is_in_scope` — read this before counting anything

`core.opportunities` and `core.jobs` carry `is_in_scope`. **False means the row belongs
to the business that used the SmartMoving account before this one.**

The `ld` account had a previous tenant. Sweeping back to 2023 on 2026-09-07 pulled in
**3,170 opportunities and 3,283 jobs** that are not this company data. They cannot be
told apart by key — quote numbers run *continuously* across the handover (…9421 then
9391…) — but their shape is unmistakable: pre-2025 `ld` rows carry no branch, no sales
agent and no lead date, where 2025+ carries all three on 100% of rows, and the two
customer bases share 50 names out of 2,892 and 2,381. `local` has the same flag on 197
rows dated 2022, which are the tail of the sweep window rather than a prior tenant.

The boundary per instance is `staging.dim_instance.data_valid_from` (`ld` 2025-01-01,
`local` 2023-01-01). Rows are **flagged, never deleted**: raw keeps what the API
returned and the exclusion stays visible and reversible. **The KPI marts filter on it;
anything counting `core` directly must too.**

### Columns added 2026-09-08

| Column | On | What it carries |
| --- | --- | --- |
| `is_in_scope` | opportunities, jobs | See above. |
| `status_subcategory` | opportunities | `lost_contact`, `lost_competitor`, `bad_duplicate`… from the `dim_status_map` seed. That seed existed, tested and documented, and **nothing read it** — three separate comments claimed a join that was never written. Wiring it took lost-reason coverage from 56.6% to 95.6%; overall 97.4%. |
| `status_category_reported` | opportunities | The category the report string implies, kept *beside* `status_category` (which comes from the authoritative platform integer) rather than merged into it. They disagree on 167 rows, and that disagreement is a finding, not noise. Never group by this. |
| `referral_channel_group` | opportunities | Paid Search / Paid Social / GBP / Organic / Referral / Affiliate / Direct / AI, from `dim_referral_source` — the other seed nothing read. Present on 90% of in-scope rows. |
| `referral_platform`, `referral_source_clean` | opportunities | Google / Meta / Bing / Yelp…, and a tidy display name. |
| `referral_is_paid` | opportunities | True when the source needs spend. **NULL, not false, when the seed is silent** — "unknown" and "free" are different answers, and an ROI denominator must not conflate them. |

WARNING: both seed joins go through `norm_text` on **both sides**, and `norm_text` can
collapse two distinct seed keys into one. In `dim_referral_source` it already does, for
two pairs of spelling variants, so that join deduplicates with `distinct on`. Singular
tests under `dbt/tests/` fail if colliding rows ever stop agreeing on what they mean —
without them the join fans out and silently multiplies opportunity rows.

**An opportunity has many jobs.** 12,251 have exactly one, 1,044 have two, 146 have
three, and a handful have more. Anything that divides an opportunity-level number
across its jobs is inventing an allocation.

**Which grain carries what** — this trips people up:

| Data                                                                                    | Lives on                           |
| --------------------------------------------------------------------------------------- | ---------------------------------- |
| Crew count, truck count, hours, hourly rate, pricing method, full actual cost breakdown | **job**                            |
| `estimated_final_total` (the quote)                                                     | **opportunity** (echoed onto jobs) |
| `invoiced_amount` — the **only** realised-revenue column in the warehouse               | **opportunity**                    |
| Status, cancellation reason                                                             | **opportunity** (copied onto jobs) |

## Money: what is revenue, what is cost

**This section was wrong until 2026-09-01 and the correction matters more than
almost anything else in this file.**

SmartMoving names the All Jobs breakdown columns `Actual Labor Cost`, `Actual
Materials Cost`, `Actual Additional Services Cost` and so on. **They are not costs.
They are REVENUE CHARGED to the customer, by line item.** The vendor's naming is
simply misleading.

Measured, not assumed — `core.jobs.total_actual_cost` against
`core.opportunities.invoiced_amount` on the 2,554 opportunities that have exactly one
job:

```
2,552 of 2,554 agree to the cent        correlation 1.0000
avg total_actual_cost 1,867             avg invoiced_amount 1,868
```

They are the same number. `invoiced_amount` is not "the only realised-revenue column
in the warehouse" — it is the only one **at opportunity grain**.

### The three money families

| Family | Columns | Grain | Means |
|---|---|---|---|
| **Quote** | `estimated_final_total`, and every `est_*_cost` | opportunity / job | What was priced |
| **Realised revenue** | `invoiced_amount` | opportunity | Total billed |
| **Realised revenue, itemised** | `total_actual_cost` and every `actual_*_cost` | **job** | Same money, broken out by line |
| **Actual cost to the company** | **`wages`** | job | What the crew was paid |

**`wages` is the only true cost column anywhere in the warehouse**, and it is what
makes gross margin computable at job grain:

```
avg actual_labor_cost (charged)   1,675
avg wages (paid)                    479     = 34.8% of labor revenue
jobs where wages exceed the charge    8  of 5,578
```

### The breakdown reconciles, once tips are included

Summing the fourteen `actual_*` components plus `actual_tax_amount`, minus
`actual_discount`:

| Sum | Jobs matching `total_actual_cost` within $1 |
|---|---:|
| components only | 3,532 of 5,752 (61%) |
| **components + `tip_amount`** | **5,066 of 5,752 (88%)** |

So `tip_amount` is part of the realised total, not an extra. The residual 12% is
rounding and edge cases; check the gap before trusting a line-item figure to the
cent.

### The API agrees with the report

`core.opportunity_charges` (`charge_kind = 'actual'`) carries the same breakdown from
the enrichment call, and it matches: **1,205 jobs with both, correlation 0.9928**,
average 3,111 (API) vs 3,086 (report). Not identical, because the API detail is a
snapshot from the moment the job closed while the report reflects the current state —
so where they differ, **the report is newer**.

### `charge_category_code`, decoded

Previously documented as "left unlabelled until the mapping is read off the
SmartMoving UI". Derived instead by correlating each category's total against the
report columns, on live data:

| Code | Category | Evidence |
|---|---|---|
| 1 | Moving labor (local, hourly) | corr 0.852 vs `actual_labor_cost` |
| 2 | Transportation / line-haul (long distance) | corr **0.999** vs `actual_labor_cost` |
| 3 | Materials and packing | corr **0.992** vs `actual_materials_cost` |
| 4 | Additional services | corr **0.996** vs `actual_additional_services_cost` |
| 7 | Valuation / replacement cost coverage | corr **1.000** vs `actual_valuation_cost` |
| 9 | Storage | few rows; names are storage charges |
| 10 | Shuttle | few rows; names are shuttle fees |

Codes 1 and 2 both land in `actual_labor_cost` on the report: for a local job the
hourly labor is the main charge, for a long-distance job the transportation charge is.

### What this unlocks

Revenue is now available **at job grain, itemised**, which removes the allocation
problem that blocked per-job revenue analysis: `invoiced_amount` sits at opportunity
grain and 1,221 opportunities have several jobs, so splitting it would have been a
fabricated allocation. `total_actual_cost` needs no splitting — and with `wages`
beside it, so does margin.

---

## `marts` — observation layer and analytics

**The `int_*` observation layer** (views) exists to resolve _disagreement_. One row =
"this source, at this time, asserted this". Nothing is resolved there; `core` resolves
it **per field** via the `pick_latest` macro, which is why a report can add
`invoiced_amount` without erasing the API's `estimated_total`.

| Object                             | Kind  | Purpose                                                              |
| ---------------------------------- | ----- | -------------------------------------------------------------------- |
| `int_opportunity_observations`     | view  | Every claim any source made about an opportunity                     |
| `int_opportunity_latest_by_source` | table | Newest per (opportunity, source) — the fan-in point                  |
| `int_job_observations`             | view  | Same, for jobs                                                       |
| `int_job_latest_by_source`         | table | Fan-in point for `core.jobs`                                         |
| `int_opportunity_quote_crosswalk`  | view  | **`(instance, quote_number)` → GUID.** The bridge every report needs |
| `int_report_all_jobs_latest`       | view  | Newest All Jobs row per job — the ~60 single-source fields           |
| `int_report_lost_leads_latest`     | view  | Newest Lost Leads row per opportunity                                |
| `int_report_cancellation_latest`   | view  | Newest Cancellation Details row per opportunity — **when** a deal died and **how much** it cost |
| `int_report_payments_latest`       | view  | The newest Payments generation, **whole**. It cannot be a per-row winner: the export carries no payment id, so its row key is the row's position in the file |
| `int_opportunity_line`             | view  | One line of business per opportunity, collapsed from its jobs. Shared by both cohort marts so the `min` tie-break exists once |
| `fct_agent_leads_daily`            | table | Sales KPIs, cohort grain: (agent, line, day the lead arrived) — 12,643 rows |
| `fct_lead_source_daily`            | table | Same cohort grain by **marketing channel** — 10,756 rows. Where ad spend attaches later |
| `fct_cancellations_daily`          | table | Cancellations on the day they **happened** — 1,007 rows. The PERIOD view. Publishes no rate, deliberately: on a calendar grain the denominator is unknowable |
| `fct_pipeline_current`             | table | Current unresolved opportunities, separating committed from speculative work; snapshot, not history |
| `mart_unmatched_report_rows`       | view  | Report rows that could not be crosswalked — a review queue. Its count oscillates; see the Lead Status note under `raw_smartmoving` |

**When a field goes through the observation layer, and when it does not:** only where
two sources can disagree. Fields with exactly one source join straight in — that is why
`int_report_all_jobs_latest` and `int_report_lost_leads_latest` exist instead of
adding sixty nullable columns to every other arm.

---

## `serving` — the published contract

Six objects, materialised as **tables** (not views) so RLS applies, each with
`entity_id` and `synced_at`, each catalogued in
[`serving_catalog.md`](serving_catalog.md). A view that is not catalogued does not exist.

| View | Grain | Rows |
| --- | --- | ---: |
| `jobs_upcoming_v1` | one per job scheduled in the next 10 days | ~390 |
| `leads_today_v1` | one per lead created today, entity-local | ~20 |
| `sales_agent_daily_v1` | `(entity_id, agent, line, lead day)` — cohort | 12,748 |
| `lead_source_daily_v1` | `(entity_id, channel, line, lead day)` — cohort | 11,181 |
| `pipeline_current_v1` | one per unresolved opportunity; current snapshot | 636 |
| `cancellations_daily_v1` | `(entity_id, agent, line, cancelled day)` — **period, not cohort** | 1,007 |

WARNING: the two cohort views carry two caveats a consumer must honour, both written
into the catalogue. Recent cohorts are not comparable to old ones — a lead from last
week has not had time to be lost, and August 2026 read 71% against a 45-50% baseline.
And `is_within_assignment` must not be used as a slicer yet: it reads false for 42% of
leads because `dim_agent_assignment` covers only 2026.

WARNING: **two cancellation views, two grains, and summing them double counts.**
`sales_agent_daily_v1.cancellation_pct` is keyed on the day the lead **arrived** — it
answers "how well does this intake hold up" and is the only grain where a cancellation
RATE has a real denominator. `cancellations_daily_v1` is keyed on the day the deal was
**cancelled** — it answers "how much did we lose in July". The same cancellation appears
in both, on two different dates. The rate formula is
`cancelled / (booked + cancelled)`, because a cancellation *replaces* the booked status
upstream (status 20 clears `is_booked`), so adding it back is what reconstructs
everything ever won.

WARNING: `cancelled_date` coverage starts **2026-01-02**, the Cancellation Details report
window, so the period view holds 1,476 of the 6,331 cancellations in `core`. The cohort
view counts all 6,331, because the cancelled flag comes from the status integer. A
disagreement between the two totals is this, not a bug.

WARNING: `materialized` here is load-bearing. `apply_rls` filters on
`table_type = 'BASE TABLE'`, so switching `serving` to views would silently drop RLS.
The catalogue calls them views in the contract sense; on disk they are tables.

---

## `raw_smartmoving` — two loaders, not one

| Written by                  | Tables                                                                   | How                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| **n8n, direct SQL**         | `webhook_events`, `report_*`                                             | The webhook receiver must record and answer 200 before processing; the report landing is an email path. |
| **dlt** (`pipeline/run.py`) | `customers_service_window*`, `opportunities_enriched*`, `leads`, `dim_*`, `quote_resolution_attempts` | Everything pulled from the API.                                                                         |

Largest tables:

| Table                         |    Rows |   Size |
| ----------------------------- | ------: | -----: |
| `report_all_jobs`             |  88,349 | 160 MB |
| `report_lead_status`          | 125,996 |  86 MB |
| `webhook_events`              |  91,650 |  61 MB |
| `report_booked_opportunities` |  37,005 |  34 MB |
| `report_lost_leads`           |  42,932 |  19 MB |

### The six report tables

| Table                         | Key             | Uniquely carries                                                                          |
| ----------------------------- | --------------- | ----------------------------------------------------------------------------------------- |
| `report_lead_status`          | `Quote #`       | The denominator — every lead regardless of outcome. `Received at`, on 100% of rows.       |
| `report_booked_opportunities` | `Quote #`       | `Invoiced Amount` — the opportunity-grain realised-revenue total.                         |
| `report_lost_leads`           | `Quote #`       | `Lost Date`, `Reason`, `Time to First Contact`.                                           |
| `report_all_jobs`             | `Job Id`        | Itemised realised revenue (misnamed `Actual * Cost` by the vendor), crew/truck counts, hourly rates and pricing method. |
| `report_cancellations`        | `Quote #`       | **`Cancelled Date`** — nothing else in the warehouse has one. Plus `Amount` and `Reason`. |
| `report_payments`             | hash of the row | `Date`, `Amount`, `Payment Category`, and links to Quote, Job **or Storage Account**.     |

⚠️ **`report_payments` is keyed on the row's POSITION plus a hash**
(`__row000123__abc`), because it has no natural key. A hash alone was tried and
failed on the first real file: SmartMoving sent 531 rows, two were byte-identical,
they hashed to the same key, and `ON CONFLICT DO NOTHING` dropped one. The row-count
check caught it — 530 landed — and blocked the dbt rebuild behind it. Position keeps
the key unique without breaking idempotency: the same email re-ingested yields the
same rows in the same order, so the same keys.

⚠️ **A payment can attach to a storage account that has no quote number.** Storage
accounts are a **third top-level entity** alongside opportunities and jobs. A payments
model needs a nullable link to each of the three plus a target discriminator — the
same shape `core.opportunity_charges` uses for estimatYed-vs-actual. Forcing every
payment under an opportunity id would drop every storage payment.

Report tables keep **every generation** — the primary key is
`(source_instance_id, report_generated_at, row_key)` with `ON CONFLICT DO NOTHING`, so
re-ingesting the same email is a no-op. `sql/34_report_retention.sql` prunes them.

⚠️ **Two different Lead Status schedules land in `report_lead_status`.** The 03:0x
generation covers `1/1/2026 → today` (~15,400 rows); every other generation covers a
rolling ~90 days (~5,200 rows). They are different reports, not fresher snapshots of
one report. Any model that filters to "the newest generation" therefore sees a
population that changes size by 3× depending on the hour — which is exactly what
`marts.mart_unmatched_report_rows` does, so its row count oscillates between ~3,000
and ~9,100 and must not be read as a trend. Discovered 2026-09-07.

### `quote_resolution_attempts` — the ledger that bounds the quote drain

One row per Quote # the backfill has asked the API about. Grain
`(source_instance_id, quote_number)`, merge.

| Column | Meaning |
| --- | --- |
| `quote_number` | The quote asked about. |
| `resolved` | Whether `/api/opportunities/quote/{n}` returned an opportunity. |
| `external_opportunity_id` | The GUID it returned, when it did. |
| `_attempted_at` | When. `run.py` re-offers a failed quote after 30 days. |

**Why it exists.** The resolver costs one call per quote, so without a memory of what
has already been asked, a nightly drain would pay for the same non-existent quote
every night forever. It deliberately records the *attempt*, not just the success — a
success is already visible in the crosswalk, and it is the failures that need
remembering.

It is **not** a deletion signal. A 404 here means SmartMoving has no opportunity under
that quote at all, which is different from one that existed and was removed; no
soft-delete marker is written. Deletions stay in `opportunity_deletions`.

---

## `staging` — 15 views and 9 seed tables

Plus, since 2026-09-14, `stg_google_ads__accounts` and `stg_google_ads__campaign_daily`
over `raw_google_ads` - `cost = cost_micros / 1,000,000` cast to `numeric` here, and the
day exposed as `spend_date_local` because Google reports by the ACCOUNT's day, not UTC.
Both build and test on zero rows today.

The 15 `stg_*` views are one per raw table: rename, type, and **cast money to
`numeric`**. That cast happens here and nowhere else, so no downstream model has to
remember it.

The 9 seeds are the business knowledge no source system holds:

| Seed                                    | Holds                                                             |
| --------------------------------------- | ----------------------------------------------------------------- |
| `dim_instance`                          | instance → entity, timezones, LOB hint, API key variable name     |
| `branch_timezone`                       | per-branch timezone override                                      |
| `dim_agent`                             | the sales roster: canonical name, aliases, role, `is_sales_agent` |
| `dim_agent_assignment`                  | agent × line of business × validity period                        |
| `dim_lob_branch`                        | branch → line of business                                         |
| `dim_opportunity_status`                | status code → boolean flags                                       |
| `dim_status_map`                        | report status string → flags                                      |
| `dim_referral_source`                   | CRM referral source -> channel, platform and paid/free classification |
| `dim_sales_team`                        | loaded for future use; currently has no model consumer             |

> ⚠️ **`dbt seed` DROPS AND RECREATES these tables on every build.** A row typed
> straight into Postgres is destroyed at the next run, silently, while dbt reports
> success — verified by experiment. Every seed table carries that warning as a
> Postgres `COMMENT`, visible in psql, DBeaver, pgAdmin and Metabase.

---

## Tenancy: `entity_id` and how isolation actually works

- **`entity_id`** = the company. **`source_instance_id`** = one SmartMoving API
  account. Many instances → one entity. Today both `ld` and `local` map to
  `ecomovers`.
- `entity_id` is present on **every** dbt-owned table in `core` (8/8), on 11 of 12
  `marts` objects (the quote crosswalk is intentionally instance-keyed), and on every
  `serving` table (5/5).

**Verified working on 2026-08-26:**

```
13 dbt-owned core/serving tables: relrowsecurity = true, 1 policy each
core.current_role_can_see() as app_read:  'ecomovers' → true,  other → false
app_read reading serving:  570 rows       reading core:  15,129 rows
app_read reading marts:    permission denied for schema marts
```

`sql/10_apply_rls.sql` and `dbt/macros/apply_rls.sql` loop over every table in `core`
and `serving` that has an `entity_id` column and attach the policy automatically — a
new table is protected with **zero per-model wiring**. The macro runs as an
`on-run-end` hook because dbt drops and recreates tables, and a dropped table takes
its policies with it.

**Granting an admin a second company is one row in `core.entity_access`** — the
primary key is `(role_name, entity_id)`, so a role can hold many.

`serving` is materialized as **tables**, not views, specifically so RLS applies. A
serving _view_ would need `security_invoker` or it would bypass the policy.

---

## Keys: enforced by tests, not by constraints

**There is exactly one constraint in the whole warehouse** — the primary key on
`core.entity_access`. No other primary keys, no foreign keys, no unique constraints.

That is deliberate and standard for an analytical warehouse: dbt drops and recreates
tables on every build, so constraints would have to be rebuilt each time and would cost
real time on bulk loads. Integrity is enforced by **dbt tests at build time** —
`not_null`, `unique` and `relationships` declared in the `_*.yml` files, and the build
fails when one breaks.

**It only works if the tests exist.** Currently enforced:

| Relationship                                               | Status                     |
| ---------------------------------------------------------- | -------------------------- |
| `core.*.<key>` uniqueness and not-null                     | ✅ tested                  |
| `dim_agent_assignment.agent_name` → `dim_agent.agent_name` | ✅ tested                  |
| `line_of_business` accepted values                         | ✅ tested                  |
| **any `entity_id` → a canonical entity list**              | ❌ **no such list exists** |

That last row is the open gap: `entity_id` is a string propagated up from raw, and
nothing checks it is a real company. A typo in a seed creates a phantom tenant
silently. Closing it is the first step of the KPI work — a `dim_entity` seed plus a
`relationships` test on every model.

### Known minor defect

`platform_rw` has no `SELECT` on `core.entity_access` (owned by `postgres`, zero
grants). RLS still works — verified above — but an operator cannot inspect who has
access to what. Fix belongs in `sql/00_bootstrap.sql`.

---

## Conventions that models rely on

- **`snake_case`**, plural tables, singular columns.
- Business keys are always `(entity_id, external_id)` — never a naked source id, because
  SmartMoving GUIDs are unique only _within_ an instance.
- Every timestamp is `timestamptz` in **UTC**. A column holding a local business date is
  suffixed `_local`.
- Money is `numeric`, cast at the `staging` boundary.
- Surrogate keys are generated in dbt, never in the pipeline.
- Every `serving` object carries `entity_id` and `synced_at`.
