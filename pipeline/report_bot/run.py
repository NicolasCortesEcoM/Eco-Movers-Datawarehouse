"""CLI entry point for the report bot.

    python -m pipeline.report_bot.run --window year --instance all
    python -m pipeline.report_bot.run --window recent --instance ld
    python -m pipeline.report_bot.run --window year --dry-run     # no browser

Exit codes, because n8n's Assert Exit Code node reads them:

    0  every enabled instance was driven successfully
    1  at least one instance failed (the others still ran)
    2  a configuration or credential problem - nothing was attempted
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from .config import ConfigError, load_config, load_instances, load_reports, resolve_window
from .smartmoving import browser_session, run_report_for_instance

log = logging.getLogger("report_bot")


def _run_dir() -> Path:
    """Screenshots and any browser temp files. Never inside the repository - it lives
    in OneDrive and does not want binary noise syncing to every machine."""
    base = Path(os.environ.get("REPORT_BOT_RUN_DIR") or Path(tempfile.gettempdir()) / "report_bot")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return base / stamp


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="report_bot",
        description="Drive the SmartMoving UI to make it email a report that cannot be scheduled.",
    )
    ap.add_argument(
        "--window",
        default="auto",
        help="year | recent | auto. Scheduled jobs should pass this explicitly - "
             "auto is for running by hand.",
    )
    ap.add_argument("--instance", default="all", help="An instance id, or 'all'.")
    ap.add_argument("--report", default="all", help="A report id, or 'all'.")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Resolve config, credentials and dates, print the plan, open no browser.",
    )
    ap.add_argument("--headful", action="store_true", help="Show the browser. For development.")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        stream=sys.stdout,
    )

    try:
        cfg = load_config()
        instances = load_instances(cfg, only=args.instance)
        reports = load_reports(cfg)
        if args.report != "all":
            reports = [r for r in reports if r.id == args.report]
            if not reports:
                raise ConfigError(f"no enabled report matches {args.report!r}")
        window = resolve_window(cfg, args.window)
    except ConfigError as exc:
        # Exit 2, distinct from a run failure: nothing was attempted, and the fix is
        # a config or an environment variable rather than a broken selector.
        log.error("configuration problem\n%s", exc)
        return 2

    log.info(
        "plan: %s | %d instance(s): %s | %d report(s): %s",
        window,
        len(instances),
        ", ".join(i.id for i in instances),
        len(reports),
        ", ".join(r.id for r in reports),
    )

    if args.dry_run:
        for inst in instances:
            for rep in reports:
                log.info(
                    "would request %-10s for %-6s -> %s  [%s .. %s]",
                    rep.id, inst.id, inst.deliver_to, window.date_from, window.date_to,
                )
        log.info("dry run: no browser opened, nothing sent")
        return 0

    run_dir = _run_dir()
    failures: list[str] = []

    with browser_session(headless=not args.headful) as context:
        for inst in instances:
            for rep in reports:
                try:
                    run_report_for_instance(context, inst, rep, window, run_dir)
                except Exception as exc:
                    # One instance failing must not cost the others their run. Every
                    # instance that CAN succeed does, and the non-zero exit at the end
                    # still raises the alert.
                    log.exception("[%s] %s failed", inst.id, rep.id)
                    failures.append(f"{inst.id}/{rep.id}: {exc}")

    if failures:
        log.error(
            "%d of %d requests failed:\n%s",
            len(failures), len(instances) * len(reports), "\n".join("  " + f for f in failures),
        )
        return 1

    log.info("all %d request(s) sent. report_ingest lands them when the emails arrive.", len(instances) * len(reports))
    return 0


if __name__ == "__main__":
    sys.exit(main())
