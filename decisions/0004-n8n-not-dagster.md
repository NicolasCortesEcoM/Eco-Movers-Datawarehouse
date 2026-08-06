# 0004 - n8n orchestrates Phase 1; Dagster is deferred

**Status:** Accepted (July 2026)

## Decision

**n8n** handles Phase 1 orchestration: scheduled polls (leads, jobs window, dims), the webhook receiver, and the email/report ingestion. **Dagster is deferred**, not adopted.

## Why

- n8n is **already self-hosted** and the team knows it. It comfortably covers a handful of independent schedules plus a webhook endpoint.
- Dagster is another service to run, monitor, and hand to a junior developer. Adopting it before it's needed adds operational surface for no gain.

## When to revisit (the trigger)

Adopt Dagster only when **n8n scheduling becomes the bottleneck**: more than ~15 interdependent jobs, or backfill/retry logic that n8n can no longer express cleanly.

## Consequences

- Schedules invoke `pipeline/run.py`; the webhook receiver writes to `raw_smartmoving.webhook_events` before any processing.
- The pipeline code stays orchestrator-agnostic (a plain CLI), so a future move to Dagster wraps `run.py` without rewriting extraction logic.
