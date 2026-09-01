# The database, as it is built

**Read this before changing anything in the warehouse.** It is the reference for what
schemas exist, what lives in each, how they relate, and which rules are enforced where.

> **Keep it current.** Any change that adds, removes or renames a schema, a `core` /
> `marts` / `serving` object, a seed, or a key relationship must update this file in
> the same commit. A stale map is worse than none.

Last verified against the live database: **2026-08-26**.

Related documents, each owning something this one does not:

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how data _moves_: the four mechanisms, the flow.
- [`crm_sync_contract.md`](crm_sync_contract.md) — **the authority** on refresh cadence and API quota.
- [`serving_catalog.md`](serving_catalog.md) — the published contract for consumers.

---

## The five schemas

| Schema                              | Industry term      | Objects                  | What it holds                                                      | Who may read it           |
| ----------------------------------- | ------------------ | ------------------------ | ------------------------------------------------------------------ | ------------------------- |
| `raw_smartmoving`                   | Bronze             | 45 tables                | Source payloads exactly as received. No transformation.            | dbt only                  |
| `staging`                           | Silver             | 9 seed tables + 15 views | Renamed, typed, lightly cleaned. **Money becomes `numeric` here.** | dbt only                  |
| `marts` (the `int_*` half)          | Silver             | 6 views                  | The observation layer — "source S said this about O at time T".    | dbt only                  |
| `core`                              | Silver (conformed) | 8 tables                 | The canonical business entities, reconciled across sources.        | dbt + read-only apps      |
| `marts` (the `fct_*`/`mart_*` half) | Gold (internal)    | 3 objects                | Analytical models. May change whenever an analyst needs it.        | analysts, BI              |
| `serving`                           | Gold (contract)    | 2 tables                 | Versioned, documented, stable.                                     | other teams' applications |

The existing names are kept rather than renamed to Bronze/Silver/Gold: renaming
schemas would break every model, the RLS script, and the consumer documentation for no
functional gain. The mapping above is the translation.

---

## `core` — the canonical entities

Every one is a **table** with an `entity_id` column and an RLS policy.

| Table                  | Grain                                                              |   Rows | Cols |
| ---------------------- | ------------------------------------------------------------------ | -----: | ---: |
| `opportunities`        | `(source_instance_id, external_opportunity_id)`                    | 15,129 |   50 |
| `jobs`                 | `(source_instance_id, external_job_id)`                            | 21,069 |   99 |
| `lines_of_business`    | one per job                                                        | 21,069 |   12 |
| `opportunity_charges`  | `(instance, external_job_id, charge_kind, seq)` — **job grain**    |  8,812 |   15 |
| `leads`                | `(source_instance_id, external_lead_id)`                           |  3,069 |   33 |
| `opportunity_payments` | `(instance, external_opportunity_id, seq)`                         |  1,654 |   13 |
| `branches`             | `(source_instance_id, branch_name)` — **the timezone authority**   |      8 |   18 |
| `agents`               | one per CRM-written salesperson name                               |     34 |    8 |
| `entity_access`        | `(role_name, entity_id)` — **access control, owned by `postgres`** |      — |    2 |

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

⚠️ **`total_actual_cost` is cost, not revenue.** Three money columns are routinely
confused: `estimated_final_total` is a quote, `total_actual_cost` is what the job cost
to run, and `invoiced_amount` is what the customer was billed. Conflating any two
misstates the business.

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
| `fct_agent_leads_daily`            | table | Sales KPIs, cohort grain: (agent, line, day the lead arrived)        |
| `mart_unmatched_report_rows`       | view  | Report rows that could not be crosswalked — a review queue           |

**When a field goes through the observation layer, and when it does not:** only where
two sources can disagree. Fields with exactly one source join straight in — that is why
`int_report_all_jobs_latest` and `int_report_lost_leads_latest` exist instead of
adding sixty nullable columns to every other arm.

---

## `raw_smartmoving` — two loaders, not one

| Written by                  | Tables                                                                   | How                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| **n8n, direct SQL**         | `webhook_events`, `report_*`                                             | The webhook receiver must record and answer 200 before processing; the report landing is an email path. |
| **dlt** (`pipeline/run.py`) | `customers_service_window*`, `opportunities_enriched*`, `leads`, `dim_*` | Everything pulled from the API.                                                                         |

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
| `report_booked_opportunities` | `Quote #`       | `Invoiced Amount` — **the only realised revenue in the warehouse**.                       |
| `report_lost_leads`           | `Quote #`       | `Lost Date`, `Reason`, `Time to First Contact`.                                           |
| `report_all_jobs`             | `Job Id`        | Actual cost breakdown, crew and truck counts, hourly rates, pricing method.               |
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

---

## `staging` — 15 views and 9 seed tables

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
| `dim_referral_source`, `dim_sales_team` | loaded, not yet read by any model                                 |

> ⚠️ **`dbt seed` DROPS AND RECREATES these tables on every build.** A row typed
> straight into Postgres is destroyed at the next run, silently, while dbt reports
> success — verified by experiment. Every seed table carries that warning as a
> Postgres `COMMENT`, visible in psql, DBeaver, pgAdmin and Metabase.

---

## Tenancy: `entity_id` and how isolation actually works

- **`entity_id`** = the company. **`source_instance_id`** = one SmartMoving API
  account. Many instances → one entity. Today both `ld` and `local` map to
  `ecomovers`.
- `entity_id` is present on **every** table in `core` (8/8), `marts` (8/9 — the quote
  crosswalk is instance-keyed) and `serving` (2/2).

**Verified working on 2026-08-26:**

```
11 core/serving tables:  relrowsecurity = true, 1 policy each
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
