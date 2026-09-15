#!/usr/bin/env python3
"""Ad-platform extraction CLI (Phase C). Lands campaign-level daily cost into
raw_<platform>, one dlt pipeline per platform.

    python run_ads.py --platform google_ads --dest postgres              # last 30 days, every child account
    python run_ads.py --platform google_ads --dest postgres --from 2023-01-01 --to 2023-12-31
    python run_ads.py --platform google_ads --dest postgres --account 1234567890 --from 2023-01-01
    python run_ads.py --platform google_ads --list-accounts               # what the manager can see; no load

Deliberately NOT a `--job` of run.py: that CLI iterates SmartMoving instances and
takes --quotes/--ids/--sweep-only, none of which mean anything here. A job that
ignores most of its own flags is a trap for the next person.

Credentials: .env (GOOGLE_ADS_DEVELOPER_TOKEN, GOOGLE_ADS_LOGIN_CUSTOMER_ID,
GOOGLE_ADS_SERVICE_ACCOUNT_JSON_B64). Postgres: the same postgres_* vars run.py uses.
See marketing_ads_integration_guide.md.
"""

from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path

import dlt

from sm_pipeline.client import load_env

DUCKDB_PATH = Path.home() / ".smartmoving_dw" / "warehouse.duckdb"

PLATFORMS = {
    # platform -> (dlt pipeline name, dataset/schema, source factory)
    "google_ads": ("google_ads_raw", "raw_google_ads"),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--platform", choices=PLATFORMS, required=True)
    ap.add_argument("--dest", choices=["duckdb", "postgres"], default="duckdb")
    ap.add_argument("--from", dest="date_from", type=date.fromisoformat,
                    help="first day to extract (YYYY-MM-DD); default: 30 days before --to")
    ap.add_argument("--to", dest="date_to", type=date.fromisoformat,
                    help="last day to extract (YYYY-MM-DD); default: yesterday")
    ap.add_argument("--account", action="append", default=[],
                    help="child account id to read (repeatable); default: every ENABLED child")
    ap.add_argument("--budget", type=int, default=50, help="max API calls this session")
    ap.add_argument("--list-accounts", action="store_true",
                    help="print the manager's account tree and exit without loading")
    args = ap.parse_args()

    if args.platform == "google_ads":
        from ads_pipeline.google_ads import GoogleAds
        from ads_pipeline.source import google_ads_source

        if args.list_accounts:
            api = GoogleAds(budget=5)
            print(f"service account : {api.service_account_email}")
            print(f"login customer  : {api.login_customer_id or '(not set)'}")
            print(f"accessible      : {api.accessible_customers()}")
            for a in api.account_tree():
                kind = "MANAGER" if a["is_manager"] else "child  "
                print(f"  L{a['level']} {kind} {a['account_id']}  {a['account_name']!r}  "
                      f"{a['status']}  {a['currency_code']}  {a['time_zone']}"
                      f"{'  TEST' if a['is_test_account'] else ''}")
            return

        source = google_ads_source(
            date_from=args.date_from, date_to=args.date_to,
            accounts=tuple(args.account) or None, call_budget=args.budget,
        )

    env = load_env()
    if args.dest == "duckdb":
        DUCKDB_PATH.parent.mkdir(exist_ok=True)
        destination = dlt.destinations.duckdb(str(DUCKDB_PATH))
    else:
        destination = dlt.destinations.postgres(
            credentials={
                "host": env["postgres_host"],
                "port": int(env["postgres_port"]),
                "username": env["postgres_user"],
                "password": env["postgres_password"],
                "database": env["postgres_db"],
            }
        )

    pipeline_name, dataset = PLATFORMS[args.platform]
    pipeline = dlt.pipeline(pipeline_name=pipeline_name, destination=destination,
                            dataset_name=dataset)
    info = pipeline.run(source)
    print(info)
    if args.dest == "duckdb":
        print(f"\nDuckDB file: {DUCKDB_PATH}")


if __name__ == "__main__":
    main()
