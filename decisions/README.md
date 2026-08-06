# Decision log (ADRs)

Short records of decisions that are **settled** - so nobody re-litigates them. Each file states the decision, why, and what would have to change to revisit it.

If you're about to argue for a separate analytical warehouse, Dagster, per-company databases, or a second API client: read the relevant record first. These were decided deliberately, not by omission.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-postgres-central-store.md) | Central store is PostgreSQL | Accepted |
| [0002](0002-instance-not-entity.md) | A SmartMoving instance is not a business entity | Accepted |
| [0003](0003-hybrid-serving-plus-core-read.md) | App teams read `serving` **and** read-only `core` | Accepted |
| [0004](0004-n8n-not-dagster.md) | n8n orchestrates Phase 1; Dagster is deferred | Accepted |
