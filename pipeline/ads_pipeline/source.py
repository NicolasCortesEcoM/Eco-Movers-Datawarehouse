"""dlt source for Google Ads raw extraction -> raw_google_ads.

Two resources:

  accounts        - the manager's account tree, replaced whole on every run. Small,
                    and the answer to "which child account is this row from" when a
                    name is needed next to an id.
  campaign_daily  - one row per (account, campaign, day). PK
                    (platform, account_id, campaign_id, date), merge disposition.

WINDOW, NOT CURSOR. The default run re-reads the last 30 days every time. Google
restates cost for the previous 2-3 days (invalid-click credits, currency, late
attribution) and conversions for up to 30 days. With merge and an overlapping window
the row for a day silently corrects itself on every run - the same reason the
SmartMoving sweep is a window and not a watermark. `--from/--to` widen it for a
backfill; the backfill is chunked by ~90 days so a failure loses one chunk, not the
whole history, and so the ledger shows progress.

ACCOUNTS ARE DISCOVERED, NOT CONFIGURED. Every run asks the manager which children
exist and reads each one. Adding a child account in Google Ads is therefore enough for
it to appear here the next day. The one thing a new account does need is a one-off
historical backfill (`--from 2023-01-01 --account <id>`), because the daily window
only reaches 30 days back. An explicit `accounts=` narrows the run for exactly that.

Rows are stamped with `_extracted_at` (UTC) like every other raw table. `date` is
landed as a DATE in the account's own time zone - Google has no other notion of a
day - and `account_time_zone` travels on the row so nobody has to guess it later.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import dlt

from .google_ads import PLATFORM, GoogleAds

DEFAULT_WINDOW_DAYS = 30
BACKFILL_CHUNK_DAYS = 92


def _chunks(date_from: date, date_to: date, size: int):
    cur = date_from
    while cur <= date_to:
        end = min(cur + timedelta(days=size - 1), date_to)
        yield cur, end
        cur = end + timedelta(days=1)


@dlt.source(name="google_ads")
def google_ads_source(
    date_from: date | None = None,
    date_to: date | None = None,
    accounts: tuple[str, ...] | None = None,
    call_budget: int = 50,
    login_customer_id: str | None = None,
):
    today = datetime.now(timezone.utc).date()
    # Yesterday is the newest CONSOLIDATED day; today's row would be partial and then
    # overwritten tomorrow anyway. Landing it buys nothing but a misleading number.
    date_to = date_to or (today - timedelta(days=1))
    date_from = date_from or (date_to - timedelta(days=DEFAULT_WINDOW_DAYS - 1))
    if date_from > date_to:
        raise ValueError(f"date_from {date_from} is after date_to {date_to}")

    api = GoogleAds(budget=call_budget, login_customer_id=login_customer_id)
    extracted_at = datetime.now(timezone.utc)

    tree = api.account_tree()
    children = [a for a in tree if not a["is_manager"] and a["status"] == "ENABLED"]
    if accounts:
        wanted = {"".join(ch for ch in a if ch.isdigit()) for a in accounts}
        missing = wanted - {a["account_id"] for a in children}
        if missing:
            raise SystemExit(f"--account not found under manager {api.login_customer_id}: "
                             f"{sorted(missing)}")
        children = [a for a in children if a["account_id"] in wanted]

    @dlt.resource(
        name="accounts",
        primary_key=("platform", "account_id"),
        write_disposition="merge",
    )
    def accounts_resource():
        for a in tree:
            yield {**a, "_extracted_at": extracted_at}

    @dlt.resource(
        name="campaign_daily",
        primary_key=("platform", "account_id", "campaign_id", "date"),
        write_disposition="merge",
        columns={
            "date": {"data_type": "date"},
            "_payload": {"data_type": "json"},
            "_extracted_at": {"data_type": "timestamp"},
        },
    )
    def campaign_daily_resource():
        for acct in children:
            for start, end in _chunks(date_from, date_to, BACKFILL_CHUNK_DAYS):
                rows = api.campaign_daily(acct["account_id"], start.isoformat(), end.isoformat())
                print(f"[{PLATFORM}] account {acct['account_id']} ({acct['account_name']}) "
                      f"{start}..{end}: {len(rows)} campaign-days")
                for r in rows:
                    r["date"] = date.fromisoformat(r["date"])
                    r["_payload"] = _json_loads(r["_payload"])
                    r["_extracted_at"] = extracted_at
                    yield r

    return accounts_resource, campaign_daily_resource


def _json_loads(s):
    import json

    return json.loads(s) if isinstance(s, str) else s
