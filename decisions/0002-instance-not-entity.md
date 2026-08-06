# 0002 - A SmartMoving instance is not a business entity

**Status:** Accepted (July 2026)

## Decision

Model **`source_instance_id`** (which SmartMoving account/API key produced a row) as distinct from **`entity_id`** (which business entity the row belongs to). A `dim_instance` seed maps instance -' entity. Primary keys are composite **`(source_instance_id, id)`**.

## Why

- The group's own company runs **two SmartMoving instances for one entity**, split by line of business (one Long Distance, one Local + Commercial). Other companies will have a single instance covering all job types. So instance -  entity in general.
- SmartMoving GUIDs are only unique **within** an instance - a naked `id` can collide across instances. Composite keys prevent that.
- Quota is **125,000 calls/month per instance**: the two-instance company has 2- - 125k, and each instance carries its own budget/ledger.
- For the split instances, the **instance itself is the most reliable line-of-business signal** (`dim_instance.lob_hint`) - more reliable than branch name, and it overrides `dim_lob_map` when present. (Confirmed live: the `local` instance even has a branch literally named "Long Distance Team".)

## Consequences

- Every raw table stamps `source_instance_id` + `entity_id`. Schedules iterate over the instance list; adding a company = one seed row + one API key.
- Timezone authority is `core.branches.timezone` (a branch sits in one zone; an entity may span zones). `dim_instance.timezone` is only a fallback default - see the timezone rules in `CLAUDE.md` and `smartmoving_sync_strategy.md` section 10.2.
