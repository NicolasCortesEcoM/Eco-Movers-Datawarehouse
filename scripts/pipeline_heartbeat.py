#!/usr/bin/env python3
"""Out-of-band liveness check for the warehouse pipeline.

Runs from CRON ON THE DROPLET, deliberately not from n8n.

    */30 * * * * cd /home/datawarehouse_user/datawarehouse && \
                 ./venv/bin/python scripts/pipeline_heartbeat.py >> /tmp/heartbeat.log 2>&1

WHAT IT IS FOR

Every other alert in this project fires when something throws. That cannot detect
silence: a job that never starts, a container that restarts mid-run, a workflow wedged
in a state where it neither errors nor progresses. `report_ingest` sat in exactly that
state from 2026-09-07 18:10 PT until a restart around 03:00 the next morning - nine
hours, 39 unread emails, zero errors, zero alerts - and then fixed itself. The stall was
found by hand, days later.

So this asks the opposite question. Not "did anything fail?" but "when did each
mechanism last SUCCEED?", and it asks from outside the thing it is watching.

WHY THE THRESHOLDS ARE LOOSE

They are alert thresholds, not the published freshness targets - those live in
crm_sync_contract.md section 8 and are not restated here. An alert threshold has to sit
well beyond normal variation or it becomes noise, and an alert nobody reads is worse
than no alert: it is the reason a real one gets scrolled past. Reports arrive six times
a day, so eight hours of silence is abnormal without being a hair trigger. Webhooks go
quiet overnight by nature, hence six hours rather than one.

EXIT CODES
    0  everything inside its threshold
    1  at least one mechanism is silent (cron mails the output; Slack gets it too if
       HEARTBEAT_SLACK_WEBHOOK is set in .env)
    2  the check itself could not run - which is also worth knowing
"""

from __future__ import annotations

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import psycopg2

REPO_ROOT = Path(__file__).resolve().parent.parent

# (mechanism, threshold hours, SQL returning one timestamptz, human detail)
CHECKS = [
    ("reports", 8.0, """
        select max(t) from (
            select max(_ingested_at) t from raw_smartmoving.report_lead_status
            union all select max(_ingested_at) from raw_smartmoving.report_all_jobs
            union all select max(_ingested_at) from raw_smartmoving.report_booked_opportunities
            union all select max(_ingested_at) from raw_smartmoving.report_lost_leads
            union all select max(_ingested_at) from raw_smartmoving.report_cancellations
            union all select max(_ingested_at) from raw_smartmoving.report_payments
        ) x""", "report_ingest has landed nothing"),

    ("webhooks", 6.0,
     "select max(received_at) from raw_smartmoving.webhook_events",
     "the SmartMoving webhook receiver has recorded nothing"),

    ("dlt_extraction", 8.0,
     "select max(inserted_at) from raw_smartmoving._dlt_loads",
     "no dlt load package has completed (opps_sweep / leads_poll)"),

    ("dbt_build", 30.0,
     "select max(synced_at) from core.opportunities",
     "core.opportunities has not been rebuilt"),
]


def load_env() -> dict:
    """Parse the repo-root .env, stripping matched surrounding quotes.

    Same rule as pipeline/sm_pipeline/client.py: the droplet .env is generated with
    every value single-quoted, and a parser that keeps the quotes hands Postgres a
    username of `'platform_rw'` and fails in a way that looks like a password problem.
    """
    env = {}
    for line in (REPO_ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
                v = v[1:-1]
            env[k.strip()] = v
    return env


def notify(env: dict, text: str) -> None:
    """Best effort. A failed notification must never mask the finding itself."""
    url = env.get("HEARTBEAT_SLACK_WEBHOOK")
    if not url:
        return
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps({"text": text}).encode(),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=15).read()
    except Exception as exc:  # noqa: BLE001
        print(f"  (slack notify failed: {type(exc).__name__}: {exc})")


def main() -> int:
    try:
        env = load_env()
        conn = psycopg2.connect(
            host=env["postgres_host"], port=int(env["postgres_port"]),
            user=env["postgres_user"], password=env["postgres_password"],
            dbname=env["postgres_db"], connect_timeout=20,
        )
    except Exception as exc:  # noqa: BLE001
        # Exit 2, not 1: "the warehouse is silent" and "I cannot see the warehouse"
        # are different problems and must not be confused for one another.
        print(f"heartbeat: CANNOT RUN - {type(exc).__name__}: {exc}")
        return 2

    now = datetime.now(timezone.utc)
    silent, rows = [], []

    with conn, conn.cursor() as cur:
        for mechanism, threshold, sql, detail in CHECKS:
            try:
                cur.execute(sql)
                last = cur.fetchone()[0]
            except Exception as exc:  # noqa: BLE001
                last = None
                detail = f"{detail} (query failed: {type(exc).__name__})"

            age = None if last is None else round((now - last).total_seconds() / 3600, 2)
            # A mechanism that has NEVER succeeded is silent by definition - `age is
            # None` must not fall through as healthy.
            is_silent = age is None or age > threshold
            rows.append((mechanism, last, age, threshold, is_silent, detail))
            if is_silent:
                silent.append((mechanism, age, threshold, detail))

            print(f"  {mechanism:16} last={last} age={age}h threshold={threshold}h "
                  f"{'SILENT' if is_silent else 'ok'}")

        cur.executemany(
            """insert into monitoring.pipeline_heartbeat
                 (checked_at, mechanism, last_success, age_hours, threshold_hrs,
                  is_silent, detail)
               values (%s, %s, %s, %s, %s, %s, %s)
               on conflict do nothing""",
            [(now, m, l, a, t, s, d) for m, l, a, t, s, d in rows],
        )

    conn.close()

    if not silent:
        print(f"heartbeat {now.isoformat(timespec='seconds')}: all mechanisms alive")
        return 0

    lines = [f":rotating_light: *Warehouse pipeline silence* ({now.isoformat(timespec='seconds')})"]
    for mechanism, age, threshold, detail in silent:
        seen = "never" if age is None else f"{age}h ago"
        lines.append(f"• *{mechanism}* — last success {seen} (threshold {threshold}h): {detail}")
    lines.append("Nothing threw an error. This is silence, which no n8n alert can see.")
    message = "\n".join(lines)

    print(message)
    notify(env, message)
    return 1


if __name__ == "__main__":
    sys.exit(main())
