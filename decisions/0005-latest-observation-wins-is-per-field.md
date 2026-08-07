# 0005 - "Latest observation wins" resolves PER FIELD, not per row

**Status:** Accepted (2026-08-05)
**Supersedes:** the row-level sketch in `smartmoving_sync_strategy.md` section 12.3

## Context

The warehouse takes facts about the same opportunity from several sources: the
opportunity detail call, the cheap customers sweep, the webhook log, and (from
Phase 5) four scheduled reports. They disagree, arrive out of order, and replay.

`smartmoving_sync_strategy.md` 12.3 sketched the resolution as:

```sql
select distinct on (entity_id, external_opportunity_id) ...
order by entity_id, external_opportunity_id, observed_at desc, source_priority
```

That picks **one whole row from one source**.

## Decision

Resolve **each field independently**: among the sources that actually reported a
value for that field, take the most recently observed non-null one. Implemented as
the `pick_latest` macro (`dbt/macros/pick_latest.sql`) over
`int_<entity>_latest_by_source`.

## Why the row-level version is wrong here

**The sources are complementary, not competing.** They do not each hold a full
picture that we choose between - they hold different, partially-overlapping
subsets:

| Source | Knows | Does not know |
|---|---|---|
| opportunity detail | leadStatus, estimated totals, charges, contacts | invoiced amount, structured addresses |
| customers sweep | status, quote number, customer, address string | any money at all |
| webhook log | status, within seconds | everything else |
| All Jobs report | structured origin/destination, actual costs, lifecycle timestamps | leadStatus, charge lines |
| Lead Status report | authoritative status + reason, received-at, time-to-contact | charges, addresses |

A row-level winner nulls out everything the winning source does not happen to
know. The 06:00 report would wipe `estimated_total` off every opportunity.

**This is not hypothetical.** Measured on the dev warehouse at the time of the
decision: **177 of 657 opportunities (27%) have a sweep observation more recent
than their enrichment.** The sweep carries no money. Under row-level resolution all
177 would lose `estimated_final_total`. Under per-field resolution all 177 keep it -
verified, zero wiped, and the total reconciles to the cent against staging.

## Consequences

- **The null-skip is load-bearing, twice.** It is what makes complementary sources
  compose. It also defuses a subtler trap: the sweep runs 5x a day and re-stamps
  its extraction timestamp even when nothing changed, so it would always
  out-timestamp an older enrichment. That is correct for fields the sweep genuinely
  knows and harmless elsewhere, because it contributes NULL there.
- **Adding a source is a `union all` arm.** `core.opportunities` and `core.jobs`
  gain branches in their `pick_latest` calls; their shape does not change. This is
  the property that makes Phase 5 cheap.
- **Every branch in one `pick_latest` call must share a SQL type.** The `VALUES`
  list type-unifies, so call sites cast explicitly.
- **Cost:** one correlated scalar subquery per resolved column. At hundreds-to-low-
  thousands of opportunities this is irrelevant. If the volume ever makes it matter,
  the fix is a lateral join or a pivot, not a return to row-level resolution.
- Line-level children (charges, payments) skip this machinery entirely: they come
  from one source and dlt replaces them wholesale on merge, so there is nothing to
  reconcile.

## Revisit if

A single source ever becomes authoritative for a whole entity, or resolution cost
shows up in build times.
