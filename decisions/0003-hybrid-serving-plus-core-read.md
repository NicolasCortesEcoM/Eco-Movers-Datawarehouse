# 0003 - App teams read `serving` and read-only `core`

**Status:** Accepted (July 2026) - Deliberately relaxes CLAUDE.md rule 6 ("no consumer reads `core`").

## Decision

App teams get a read-only role (`app_read`) with `SELECT` on both **`serving`** (the stable, versioned contract) **and `core`** (canonical entities, under an explicit *"unstable - may change without a version bump"* label). No consumer gets access to `raw_*` or `staging`, and no consumer ever gets a vendor API key.

## Why

- Strict serving-only is the cleanest contract, but it makes the one-person platform team the **bottleneck for every new field** an app needs. When a team is blocked waiting on a serving view, the temptation is to call the vendor API directly - which is the exact failure this whole project exists to prevent.
- Letting trusted teams read `core` lets them build app-specific `marts` themselves, removing that bottleneck, while the platform team still owns the expensive, quota-bound, shared parts (extraction + canonical entities).

## The trade-off (accepted, not ignored)

`core` has **no stability guarantee**. Teams that build on it accept breakage when models change. The moment a `core`-derived query becomes load-bearing for an app, that's the signal to promote it into a versioned `serving` view. Track those requests - a team wanting a serving view is the catalog telling you where the next contract goes.

## Consequences

- RLS on `entity_id` applies to `core` and `serving` alike, so cross-entity isolation holds regardless of which layer a consumer reads.
- `serving_catalog.md` documents `serving`; `consuming_serving_data.md` explains the access model, including the `core` caveat.
