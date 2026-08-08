---
name: smartmoving-api
description: How to call the SmartMoving External API from this repo - two instances, quota discipline, pagination, date formats, and the reusable client. Use whenever making real requests to SmartMoving or writing extraction code.
---

# SmartMoving API - calling conventions for this project

## Instances and credentials

This company runs **two SmartMoving instances for ONE business entity**, split by line of business. Keys live in `.env` (gitignored, never commit or print them):

| Instance id | Env var | Line of business |
|---|---|---|
| `ld` | `SMARTMOVING_API_KEY_LD` | Long Distance / Interstate |
| `local` | `SMARTMOVING_API_KEY_LOCAL` | Local + Commercial |

Other group companies will have a single instance. Everything is parametrized by `source_instance_id`; GUIDs are only unique per instance -' composite keys (`source_instance_id`, `id`).

## Quota discipline (non-negotiable)

- **125,000 calls/month PER instance.** Every request counts - each page, each error.
- **Log every call** to `scripts/api_call_log.jsonl` (the client does this automatically). Never call the API with ad-hoc curl that skips logging.
- Prefer date-window endpoints over full sweeps; prefer reprocessing already-landed raw data over re-calling.
- Exploration sessions: budget <=50 calls/instance, count before you start.

## Request basics

- Base URL: `https://api-public.smartmoving.com/v1`
- Auth header: `x-api-key: <key>` (Premium on both instances)
- Pagination: `Page` + `PageSize` - **server caps PageSize at 200** (verified live; asking for more silently returns 200). Loop until `lastPage: true` in the envelope. Response field is `pageNumber`, request param is `Page`.
- `/api/customers?IncludeOpportunityInfo=true` is slow (3 - 6 s/page) - don't parallelize aggressively.
- Dates: filters are **integers `YYYYMMDD`** (e.g. `20260718`). Timestamps `*_Utc` are ISO strings in UTC. `serviceDate` is a local business date - never timezone-convert it.
- Enum fields appear as `{}` in the scraped docs (`smartmoving_api_docs/`) - real values must come from live responses or the reference-list endpoints.
- **~120 calls/minute trips `429 Rate limit is exceeded`** - measured live, not documented by the vendor. Throttle with `pace`; back off on 5xx, hard-stop on 4xx. **429s and 4xx still consume quota.**
- `Include*` flags on opportunity detail do NOT change quota cost - always request all of them when enriching.

## Reusable client

Use `scripts/sm_client.py`:

```python
from sm_client import SmartMoving
sm = SmartMoving("ld")          # or "local"
sm.get("/api/ping")
list(sm.paginate("/api/branches", PageSize=100))
sm.calls_made                    # session counter
```

It reads `.env` from the repo root, logs every call (instance, endpoint, params, status, rows, duration) to `scripts/api_call_log.jsonl`, and raises after a configurable per-session call budget (`SmartMoving("ld", budget=50)`).

## Reference docs in this repo

- `smartmoving_api_complete_reference.md` - every endpoint, params, response shapes.
- `smartmoving_sync_strategy.md` - which mechanism (webhook/poll/report) each entity uses; read before adding extraction.
- `smartmoving_api_findings.md` - ground truth from live exploration (real enums, volumes). Update it when you learn something new from the live API.
