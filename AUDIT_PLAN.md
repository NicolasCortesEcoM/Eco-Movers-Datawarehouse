# Warehouse audit + sales KPI layer — working plan

> **What this file is.** The live task board for the audit that started 2026-09-07 and
> the sales KPI layer that came out of it. It is updated in the same commit as the work
> it describes, so it is always the current picture.
>
> **How it relates to the other docs.** [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md)
> remains the plan of record for the project as a whole; this file is one workstream
> inside it, at task granularity. [`crm_sync_contract.md`](crm_sync_contract.md) still
> outranks both on cadence, quota and mechanism. Nothing here restates a number that
> belongs to the contract.
>
> **Status vocabulary:** ✅ done and verified · 🔄 in progress · ⏳ not started ·
> ⛔ blocked (says on what).

**Last updated:** 2026-09-08 05:30 PT.

---

## Why this work exists

A full review of the repository and the live warehouse was asked for: faults, gaps,
badly-generated views, inconsistencies, duplicates and redundant tables — and on top of
that, a sales KPI layer complete enough to retire external applications.

The structural health turned out to be good: zero grain violations, zero duplicate
business keys, zero orphan jobs, every view building. What the audit found instead was
a dated time bomb, a stalled ingestion flow, a month-old piece of pipeline state that
had already destroyed data once, and two fully-built seeds that nothing read — which
turned out to be exactly what the chosen KPIs needed.

**Agreed scope:** the Data Warehouse only (`raw_smartmoving` / `staging` / `core` /
`marts` / `serving`). Three other applications share this database and are reported as
findings in section D, but are neither modified nor depended on.

**Agreed KPIs:** per-agent sales dashboards · pipeline and forecast · lead sources and
quality. Phone activity is out of scope (it needs RingCentral).

---

## Progress at a glance

| | Done | In progress | Pending | Blocked |
|---|---:|---:|---:|---:|
| A — critical defects | 4 | 0 | 0 | 0 |
| B — KPI layer | 4 | 0 | 2 | 0 |
| C — modelling defects | 3 | 0 | 5 | 0 |
| D — redundancy cleanup | 0 | 0 | 1 | 0 |

`dbt build`: **PASS=277, ERROR=0** (222 when the audit started).
Both marts reconcile exactly against `core`: 53,910 = 53,910.
Warehouse: 58,573 opportunities · 63,440 jobs · 36,847 leads · 2,133 MB · disk 42%.
Committed on branch `warehouse-audit-and-sales-kpis` (commit `cfae435`).

---

## A. Critical defects

### ✅ A1 — Retention would have deleted the 2023-2025 history on 2026-09-17
`sql/34_report_retention.sql` keeps one generation per instance per calendar day for
anything older than 10 days. The historical backfill landed 15 generations on a single
Pacific day holding **different years** of data, so the pass would have kept one of each
group and silently destroyed 2023 and 2024. Row counts would have looked healthy.

**Done:** `_is_historical_backfill` on the four pruned tables
(`sql/36_historical_backfill_marker.sql`), 15 generations and 133,381 rows flagged,
`sql/34` skips them in both the ranking and the delete.
**Verified:** zero generations are both flagged and unflagged — the only failure mode.

### ✅ A2 — `report_ingest` stalled for nine hours, and recovered on a restart
From 2026-09-07 18:10 PT nothing was collected: all 39 SmartMoving emails sat unread and
the 21:00 batch had still not landed at 21:34, while n8n itself was demonstrably alive
(webhooks arriving, dlt running on schedule). The 31 pending reports were loaded by hand
and the 34 processed emails marked read.

**Resolved, but not by a fix.** The n8n containers restarted around 03:00 PT on 09-08 and
ingestion resumed on its own: the 03:03 generations landed normally at 03:13, with zero
ingest errors. Verified afterwards - payments did **not** duplicate (162,660 rows =
162,660 distinct keys, so marking the processed emails read did its job), and the 15
protected historical generations are intact.

⚠️ **The root cause is unknown and unaddressed.** A stuck workflow cleared itself by
chance after nine hours, and nothing anywhere would have reported it. That is precisely
the failure class A4 exists to catch, and it is the strongest argument for building it:
without a heartbeat, the next stall is equally invisible and might not restart itself.

### ✅ A3 — A month-old presence proof was still deciding what counted as deleted
`_dlt_pipeline_state` held `{at: 2026-08-08, from: 20250204, to: 20270204}`, written by
a `--sweep-only` backfill that recorded no sightings at all. Five days later the
deletion pass marked **550 `ld` opportunities as vanished**; four were re-checked
against the API a month on and all four were alive, two of them Booked with a future
service date. 203 were still flagged.

**Done:** the 203 were re-verified against the API (204 calls, **all HTTP 200, zero
404s**) and cleared — `core` now has zero rows flagged deleted. `sweep_only` no longer
writes the presence note, and — the general fix — the deletion pass now **refuses any
presence proof older than two days** (`SWEEP_PROOF_MAX_AGE`). A stale sweep proves
nothing about absence, so the safe failure mode is to do nothing; real deletions still
come through the `opportunity-deleted` webhook's 404 path, which is direct evidence
rather than inference.

### ✅ A4 — Nothing detected an n8n execution that *dies*
Every alerting mechanism in the project lives *inside* an execution: a node throws and
`errorWorkflow` catches it. An execution killed by the OOM reaper, a container restart
mid-run, or a schedule trigger that never fires produce **no signal at all** — which is
exactly how A2 went unnoticed. The one liveness check (`Assert Serving Is Fresh`) is
evaluated only inside the 03:30 build, so if that execution is the one that dies,
nothing evaluates it.

**Done.** `scripts/pipeline_heartbeat.py` + `monitoring.pipeline_heartbeat`
(`sql/37_pipeline_heartbeat.sql`), on cron at :05/:35 — outside n8n on purpose. It
checks four mechanisms (reports, webhooks, dlt extraction, dbt build) and asks when each
last *succeeded*, not whether anything threw.

**Verified both ways**, because a silence detector that has never fired is not a
detector: with real thresholds all four report alive; with thresholds forced to four
minutes all four flag `SILENT`, the alert message formats, exit code is 1, and the rows
land in the table. Test rows were then deleted so the table does not lie.

Every run is recorded, not just the bad ones — a heartbeat table with no recent
heartbeat is the only way to notice that the monitor itself stopped.

⚠️ **One value still needed from you:** set `HEARTBEAT_SLACK_WEBHOOK` in the droplet
`.env` to a Slack incoming-webhook URL. Until then the check runs, records and exits
non-zero, but the finding only reaches cron's local mail — which nobody reads.

---

## B. The sales KPI layer

### ✅ B0 — Wire the two orphaned seeds
Both were seeded, tested and documented from the start, and read by nothing.

- **`dim_status_map`** — three separate comments in the repo asserted a join to it that
  **was never written**. Now joined in `core.opportunities` via `norm_text`, contributing
  `status_subcategory` and `status_category_reported`. Three missing rows added from
  measured unmatched values.
  **Lost-reason coverage: 56.6% → 95.6%.** Overall subcategory coverage 97.4%.
- **`dim_referral_source`** — now gives `referral_channel_group`, `referral_platform`,
  `referral_is_paid`, `referral_source_clean`. **Channel on 90%** of in-scope
  opportunities, paid/unpaid on 99%.

Both joins are guarded against fan-out by singular tests, because `norm_text` can
collapse distinct seed keys into one — and in `dim_referral_source` it already does, for
two pairs of spelling variants.

### ✅ B1 — Per-agent sales mart
`marts.fct_agent_leads_daily` extended, not duplicated: loss breakdown
(`lost_to_competitor`, `lost_on_price`, `lost_no_contact`, `lost_to_diy`,
`lost_reason_unknown`), realised deal size, and the prior-tenant filter.

### ⏳ B2 — Pipeline and forecast
Not started. Calibration note that must survive into the model: the open pipeline is
**small** — 214 open and 414 booked, of which 329 booked ($968K) and 163 open ($1.23M)
are future-dated. The value here is *revenue already committed*, not a speculative
funnel, and it should not be presented as more than that.

### ✅ B3 — Lead source / quality mart
`marts.fct_lead_source_daily`, 10,756 rows, 2023-01-01 → 2026-09-07, cohort grain
`(entity_id, channel_group, line_of_business, lead_received_date)`. This is where
marketing spend attaches later: cost per lead, CAC and ROAS become joins at
`(date, channel)`, not new models.

### ✅ B4 — Publish to `serving` (partial)
`serving.sales_agent_daily_v1` (12,643 rows) and `serving.lead_source_daily_v1`
(10,756 rows), both catalogued in `serving_catalog.md`, both RLS-enabled, both verified
queryable by `app_read`. Also added the `relationships` tests back to `core` that the
two pre-existing serving views never had.

**Still pending:** `serving.opportunities_v1`, the view the project has declared its
number-one priority since the beginning.

### Added outside the original plan — prior-tenant isolation
The sweep back to 2023 pulled in the business that used the `ld` SmartMoving account
before 2025: **3,170 opportunities and 3,283 jobs**. Pre-2025 `ld` rows carry no branch,
no sales agent and no lead date where 2025+ carries all three on 100% of rows, and the
customer bases are disjoint — 50 shared names out of 2,892 and 2,381. Quote numbers run
*continuously* across the handover, so the split can only be a date.

`dim_instance.data_valid_from` (`ld` 2025-01-01, `local` 2023-01-01) drives `is_in_scope`
on `core.opportunities` and `core.jobs`. Rows are **flagged, never deleted** — raw keeps
what the API returned and the exclusion stays visible and reversible. The KPI marts
filter on it.

---

## C. Modelling and consistency defects

| # | Finding | Status |
|---|---|---|
| C1 | `core.lines_of_business` had **no YAML entry and zero tests** while feeding a mart | ✅ documented and tested |
| C2 | `_core.yml` defined `opportunity_charges` **twice** with contradictory grain descriptions. It does **not** break the build — verified — the second block silently wins | ✅ stale block removed |
| C3 | `core.agents` tested `unique` on the name when the grain is `(entity_id, source_agent_name)`; passes only while there is one entity | ✅ singular test on the pair |
| C4 | `report_cancellations` and `report_payments` are **not even declared as sources** and have no staging model. `Cancelled Date` exists nowhere else; payments are the only link to storage accounts | ⏳ |
| C5 | The Booked-report join is duplicated between `int_opportunity_observations` and the `bkd_extra` CTE in `core/opportunities.sql` — the one report that never got its own `int_report_*_latest` | ⏳ |
| C6 | `--max-pages` is **not propagated** to `--job jobs` or the dims pulls, which still truncate silently at 50 pages | ⏳ |
| C7 | `--ids` together with `--quotes` makes the source yield two resources with the same name; nothing rejects it | ⏳ |
| C8 | The contract says `dbt_build_reports` runs the retention prune; **the workflow only runs `dbt seed && dbt build`**. The cron is documented four different ways | ⏳ |

Also fixed along the way: `_marts.yml` used the deprecated `tests:` key throughout — 15
occurrences migrated to `data_tests:`.

---

## D. Redundancy and cleanup — ⏳ not started

**Inside the warehouse:** 8 source declarations nothing reads; a stale description
claiming `report_lost_leads` is "deliberately not modelled" when it is;
`jobs.json` (a sample report row, referenced by nothing); `.notes.json`; the empty
`.agents/`; `scripts/sm_client.py`, which **no file imports** although `CLAUDE.md` rule 2
mandates its use; `OLD_TABLES/SCRDLA - dim_lob_map.csv` for a seed deleted in August;
9 of 11 weekly `dim_*` pulls that nothing reads; and `smartmoving_sync_strategy.md`,
which names workflows that no longer exist.

**Outside the agreed scope — reported only.** This database is shared by at least three
other applications:

- **`qc`** (25 tables) — includes `qc.smartmoving_jobs`, 1,859 rows of quote, status,
  amounts, salesperson and dates: **duplicate extraction from SmartMoving**, precisely
  what the warehouse exists to prevent under priority #1 of `CLAUDE.md`. Also
  `qc.agents` (101 rows with `extension_number`) and 17,226 call recordings with
  transcripts. `qc.call_scores` and `qc.qc_metrics` are empty.
- **`workspace` / `ecoworkspace`** — exact duplicates of each other (13,217 tasks and
  60 projects each). Looks like a half-finished rename.
- **`raw_ringcentral.calls`** — 17,226 calls, 2026-04-09 → today, live. Carries a
  datable defect: `call_direction` switched from lower-case to capitalised on
  **2026-09-04**, which splits any grouping by direction. For when it enters scope:
  **92.4% of dialled numbers (3,840 of 4,154) match a customer phone** in `core`, so
  call-to-opportunity attribution is very achievable.

---

## Corrections made during execution

Recorded because each was a wrong turn caught by measurement, and the reasoning is worth
keeping:

- The first backfill marker used a correlated `NOT EXISTS` and ran **over ten minutes**
  on one table before being killed. Rewritten set-based: **7.2 seconds**.
- The obvious content rule ("protect a generation whose data predates its generation
  year") **over-fires** — it also protects ten routine `ld` Booked generations, because
  Long Distance has no 2026 booked date at all. Pinned to the actual load window instead.
- `dbt_utils` **is not installed** in this project and there is no `packages.yml`; a
  composite-uniqueness test using it would have broken the build. Replaced with singular
  tests, which the project already has a path for.
- `dim_referral_source.is_paid` is loaded as a **boolean**, not text.
- **`quoted_leads` was removed rather than shipped.** The estimate is never null, and
  `> 0` does not indicate a quote: opportunities with a zero estimate convert at 50.0%
  and those with a positive one at 48.9%. A metric that looks like a funnel step and
  is not one does more harm than its absence.
- **Deal size moved off the estimate.** `estimated_final_total` is zero on 45% of booked
  opportunities and would have reported **$1,151 against a true $2,085**. Now computed
  from `invoiced_amount`, present on 96% of booked deals. 2025 average: **$1,914**.

---

## Two caveats that ship with the KPI views

Both are written into `serving_catalog.md` as well, because a consumer who ignores them
gets wrong answers with no error.

1. **Recent cohorts are not comparable to old ones.** A lead from last week has not had
   time to be lost, so its cohort looks inflated — August 2026 read 71% against a 45-50%
   baseline. Exclude the last ~60 days, or show `open_leads` beside the rate.
2. **Do not slice by `is_within_assignment` yet.** It reads `false` for 42% of leads
   because `dim_agent_assignment` was built for 2026 and the 2023-2025 history falls
   outside its validity windows. Seed work, not code. Related: 34 of the 65 salesperson
   names in the data are not in `dim_agent` at all.
