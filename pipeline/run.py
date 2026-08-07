"""Run the SmartMoving extraction pipeline.

Examples:
    python run.py --job all --instance all                # everything, both instances
    python run.py --job leads --instance local            # today's leads, local only
    python run.py --job leads --leads-from 20260601 --leads-to 20260718 --instance all
    python run.py --job jobs --days-ahead 10 --instance all
    python run.py --job enrich --instance all --dest postgres      # wide sweep + full enrichment of changed opps
    python run.py --job enrich --from-offset -7 --to-offset 30 --instance all
    python run.py --ids 1a2b,3c4d --instance ld --dest postgres    # targeted enrichment (webhook worker)
    python run.py --job dims --instance all

Destination:
    duckdb (default)  -> local dev file at ~/.smartmoving_dw/warehouse.duckdb
                         (outside OneDrive on purpose)
    postgres          -> the central store. Reads the .env postgres_* vars
                         (postgres_host/port/user/password/db). See README.md.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import dlt

from sm_pipeline.client import load_env
from sm_pipeline.instances import INSTANCES
from sm_pipeline.source import smartmoving_source

DUCKDB_PATH = Path.home() / ".smartmoving_dw" / "warehouse.duckdb"

JOB_MAP = {
    "leads": ("leads",),
    "jobs": ("jobs_window",),
    "enrich": ("enrich",),  # wide sweep [from_offset,to_offset] + diff-driven full enrichment
    "dims": ("dims",),
    "all": ("leads", "jobs_window", "dims"),
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--job", choices=JOB_MAP, default="all")
    ap.add_argument("--instance", choices=[*INSTANCES, "all"], default="all")
    ap.add_argument("--dest", choices=["duckdb", "postgres"], default="duckdb")
    ap.add_argument("--leads-from", type=int, default=None, help="YYYYMMDD; default: today (entity tz)")
    ap.add_argument("--leads-to", type=int, default=None, help="YYYYMMDD; default: today (entity tz)")
    ap.add_argument("--days-ahead", type=int, default=10, help="service-date window size for the jobs sweep")
    ap.add_argument("--from-offset", type=int, default=-7, help="enrich sweep start, days from today (entity tz)")
    ap.add_argument("--to-offset", type=int, default=30, help="enrich sweep end, days from today (entity tz)")
    ap.add_argument("--ids", default=None, help="comma-separated opportunity ids: targeted enrichment, no sweep (webhook worker)")
    ap.add_argument("--budget", type=int, default=300, help="max API calls per instance per run")
    ap.add_argument("--pace", type=float, default=0.6, help="seconds between API calls (rate-limit throttle)")
    ap.add_argument("--hot-ttl-hours", type=float, default=24.0,
                    help="re-enrich opps with a service date in [today-3, today+21] older than this")
    ap.add_argument("--cold-ttl-hours", type=float, default=336.0,
                    help="re-enrich every other opp in the sweep window older than this (safety net)")
    ap.add_argument("--refresh-stale-hours", type=float, default=None,
                    help="force re-enrichment of anything last enriched more than N hours ago")
    args = ap.parse_args()

    # Targeted enrichment (--ids) runs enrichment only, no sweep/leads/dims.
    opp_ids = tuple(i.strip() for i in args.ids.split(",") if i.strip()) if args.ids else None

    if args.dest == "duckdb":
        DUCKDB_PATH.parent.mkdir(exist_ok=True)
        destination = dlt.destinations.duckdb(str(DUCKDB_PATH))
    else:  # postgres - build credentials from the .env postgres_* vars
        env = load_env()
        destination = dlt.destinations.postgres(
            credentials={
                "host": env["postgres_host"],
                "port": int(env["postgres_port"]),
                "username": env["postgres_user"],
                "password": env["postgres_password"],
                "database": env["postgres_db"],
            }
        )

    pipeline = dlt.pipeline(
        pipeline_name="smartmoving_raw",
        destination=destination,
        dataset_name="raw_smartmoving",
    )

    instances = list(INSTANCES) if args.instance == "all" else [args.instance]
    for inst in instances:
        source = smartmoving_source(
            inst,
            jobs=() if opp_ids else JOB_MAP[args.job],
            leads_from=args.leads_from,
            leads_to=args.leads_to,
            days_ahead=args.days_ahead,
            from_offset=args.from_offset,
            to_offset=args.to_offset,
            opp_ids=opp_ids,
            call_budget=args.budget,
            pace=args.pace,
            hot_ttl_hours=args.hot_ttl_hours,
            cold_ttl_hours=args.cold_ttl_hours,
            refresh_stale_hours=args.refresh_stale_hours,
        )
        info = pipeline.run(source)
        print(f"[{inst}] {info}")

    if args.dest == "duckdb":
        print(f"\nDuckDB file: {DUCKDB_PATH}")


if __name__ == "__main__":
    main()
