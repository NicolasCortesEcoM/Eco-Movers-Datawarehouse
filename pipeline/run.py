"""Run the SmartMoving extraction pipeline.

Examples:
    python run.py --job all --instance all                # everything, both instances
    python run.py --job leads --instance local            # today's leads, local only
    python run.py --job leads --leads-from 20260601 --leads-to 20260718 --instance all
    python run.py --job jobs --days-ahead 10 --instance all
    python run.py --job enrich --instance all --dest postgres      # wide sweep + full enrichment of changed opps
    python run.py --job enrich --from-offset -180 --to-offset 60 --instance all
    python run.py --job enrich --sweep-only --instance all --dest postgres    # crosswalk only, no detail calls
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
    # ONE window on EVERY run - the authority is crm_sync_contract.md section 6,
    # and scripts/check_sync_contract.py fails the build if these defaults drift
    # from it. The sweep costs ~1 call per 200 customers, so a wide window is
    # nearly free, while a narrow one starves the GUID<->quote crosswalk the
    # reports need. Using a single window everywhere also removes the old
    # two-different-narrow-windows bug, where the scheduled sweep and the nightly
    # reconciliation thrashed each other's presence set into false deletions.
    ap.add_argument("--from-offset", type=int, default=-180, help="enrich sweep start, days from today (entity tz)")
    ap.add_argument("--to-offset", type=int, default=60, help="enrich sweep end, days from today (entity tz)")
    ap.add_argument("--ids", default=None, help="comma-separated opportunity ids: targeted enrichment, no sweep (webhook worker)")
    ap.add_argument("--budget", type=int, default=300, help="max API calls per instance per run")
    ap.add_argument("--pace", type=float, default=0.6, help="seconds between API calls (rate-limit throttle)")
    ap.add_argument("--hot-ttl-hours", type=float, default=24.0,
                    help="re-enrich opps with a service date in [today-3, today+21] older than this")
    ap.add_argument("--cold-ttl-hours", type=float, default=336.0,
                    help="re-enrich every other opp in the sweep window older than this (safety net)")
    ap.add_argument("--refresh-stale-hours", type=float, default=None,
                    help="force re-enrichment of anything last enriched more than N hours ago")
    ap.add_argument("--sweep-only", action="store_true",
                    help="run ONLY the customers sweep - no per-opportunity detail calls, no "
                         "deletion pass. The sweep returns the opportunity GUID and quote number "
                         "for ~1 call per 200 customers, so this is the cheap way to widen the "
                         "GUID<->quote crosswalk over a long history.")
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
    # One instance failing must not silently skip the others. The instances have
    # separate API keys and separate quotas, so a problem with one says nothing
    # about the other - but with a bare loop, `ld` blowing up meant `local` never
    # ran and nobody could tell from the output that half the job was missing.
    failures: list[str] = []
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
            sweep_only=args.sweep_only,
        )
        try:
            info = pipeline.run(source)
            print(f"[{inst}] {info}")
        except Exception as exc:  # noqa: BLE001 - the next instance must still run
            # Exhausting the call budget is a GUARDRAIL doing its job, not a
            # failure: the run stops early, keeps what it fetched, and the next
            # run resumes from the same watermark. Reporting it as a failure would
            # make every scheduled run alert while a backlog is being absorbed -
            # and an alert that always fires is an alert nobody reads.
            if "budget" in str(exc).lower():
                print(f"[{inst}] call budget reached - partial run, resuming next time")
                continue
            failures.append(inst)
            print(f"[{inst}] FAILED: {type(exc).__name__}: {exc}")

    if args.dest == "duckdb":
        print(f"\nDuckDB file: {DUCKDB_PATH}")

    # Exit non-zero so the caller can tell. The n8n SSH nodes wrap this in
    # `out=$(...); rc=$?; ...; exit $rc` and assert on rc - without a non-zero exit
    # here a failed instance would look like a clean run.
    if failures:
        raise SystemExit(f"extraction failed for: {', '.join(failures)}")


if __name__ == "__main__":
    main()
