#!/usr/bin/env python3
"""Land a SmartMoving report exported BY HAND (xlsx) into raw_smartmoving.report_*,
using the exact landing contract of the n8n report_ingest path.

    python scripts/load_report_export.py --report payments --instance local Payments/payments.xlsx
    python scripts/load_report_export.py --report payments --instance ld "Payments/payments LD 2.xlsx" --dry-run

When to use it: a report whose scheduled export only covers a rolling window (Payments:
90 days) has history that report_ingest never saw. Export the missing range from the
SmartMoving UI, run this once per file, delete the file. NOT part of the pipeline; it
never runs on a schedule.

Contract honoured (sql/30-35, deploy/n8n_report_ingest_nodes.json):
  * one row per report row, the cells verbatim in `row_data` jsonb, keyed by the row's
    POSITION (`__row000123`) within the generation - blanks stay '', numbers stay
    numbers, dates stay the 'M/D/YYYY' strings SmartMoving writes;
  * `report_generated_at` is the export's own timestamp (the xlsx file's mtime, UTC)
    so the generation is distinct from every scheduled one and a re-run of the same
    file is a no-op (ON CONFLICT DO NOTHING on the primary key);
  * `_source_email` records the file name, so the generation can be traced.

The dbt side does the rest: int_report_payments_all unions every generation and
deduplicates by transaction identity, so a payment present in both a manual export
and a scheduled window appears once.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

import openpyxl
import psycopg2
from psycopg2.extras import Json, execute_values

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "pipeline"))
from sm_pipeline.client import load_env  # noqa: E402

# report -> (raw table, the cell that marks the header row)
REPORTS = {
    "payments": ("report_payments", "Quote"),
    "cancellations": ("report_cancellations", "Quote"),
}
ENTITY_ID = "ecomovers"


def read_rows(path: Path, header_marker: str) -> tuple[list[str], list[dict]]:
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    try:
        hi = next(i for i, r in enumerate(rows) if r and r[0] == header_marker)
    except StopIteration:
        raise SystemExit(f"{path}: no header row starting with {header_marker!r}")
    header = [str(c) for c in rows[hi] if c not in (None, "")]
    out = []
    for r in rows[hi + 1:]:
        cells = list(r[:len(header)])
        if all(c in (None, "") for c in cells):
            continue
        rec = {}
        for k, v in zip(header, cells):
            if v is None:
                v = ""
            elif isinstance(v, (dt.datetime, dt.date)):
                v = f"{v.month}/{v.day}/{v.year}"
            rec[k] = v
        out.append(rec)
    return header, out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--report", choices=REPORTS, required=True)
    ap.add_argument("--instance", choices=["local", "ld"], required=True)
    ap.add_argument("--dry-run", action="store_true", help="parse and report, write nothing")
    args = ap.parse_args()

    table, marker = REPORTS[args.report]
    env = load_env()
    conn = None
    if not args.dry_run:
        conn = psycopg2.connect(host=env["postgres_host"], port=int(env["postgres_port"]),
                                user=env["postgres_user"], password=env["postgres_password"],
                                dbname=env["postgres_db"])
    for path in args.files:
        header, recs = read_rows(path, marker)
        generated_at = dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc)
        dates = [r.get("Date") for r in recs if r.get("Date")]
        span = ""
        try:
            parsed = sorted(dt.datetime.strptime(d, "%m/%d/%Y").date() for d in dates)
            span = f"{parsed[0]}..{parsed[-1]}" if parsed else ""
        except ValueError:
            pass
        print(f"{path.name}: {len(recs)} rows, {len(header)} columns, dates {span}, "
              f"generation {generated_at.isoformat(timespec='seconds')}")
        if args.dry_run or not recs:
            continue
        values = [(args.instance, ENTITY_ID, generated_at, f"__row{i:06d}", Json(rec), f"manual-export:{path.name}")
                  for i, rec in enumerate(recs)]
        with conn, conn.cursor() as cur:
            cur.execute(f"select count(*) from raw_smartmoving.{table} where source_instance_id=%s and report_generated_at=%s",
                        (args.instance, generated_at))
            before = cur.fetchone()[0]
            execute_values(cur, f"""insert into raw_smartmoving.{table}
                (source_instance_id, entity_id, report_generated_at, row_key, row_data, _source_email)
                values %s on conflict do nothing""", values, page_size=1000)
            cur.execute(f"select count(*) from raw_smartmoving.{table} where source_instance_id=%s and report_generated_at=%s",
                        (args.instance, generated_at))
            after = cur.fetchone()[0]
        print(f"  landed {after - before} new rows (generation now holds {after})")
    if conn:
        conn.close()


if __name__ == "__main__":
    main()
