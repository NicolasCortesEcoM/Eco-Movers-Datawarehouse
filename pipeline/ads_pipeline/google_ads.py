"""Google Ads API client - the only way this repository talks to Google Ads.

Mirror of sm_pipeline/client.py, with the same obligations:

- Credentials come from the repo-root .env, never from the command line, never from
  a file on disk. The service-account key is stored base64-encoded in one variable
  (GOOGLE_ADS_SERVICE_ACCOUNT_JSON_B64) and decoded IN MEMORY, because the droplet
  .env is the only secret carrier deploy/sync_droplet.py knows how to ship, and a
  multi-line PEM does not survive a `source`d .env.
- Every call is appended to scripts/api_call_log.jsonl with source="google_ads".
  One ledger for every source; that is how anyone can see who spends what.
- A per-session call budget. Google Ads is free and a daily extraction is a handful
  of calls, so the budget here is insurance against a loop, not against a quota.
- Retry with backoff on RESOURCE_EXHAUSTED / UNAVAILABLE / DEADLINE_EXCEEDED, never
  on authentication or authorization errors - a bad token does not get better by
  asking again.

ACCOUNT STRUCTURE, because it decides the primary key downstream. The developer
token belongs to a MANAGER account (MCC). The service account was added as a user of
that manager, so `list_accessible_customers` returns the manager, and every request
carries `login-customer-id = manager` while `customer_id` is the CHILD account being
read. Children are discovered on every run from the `customer_client` resource under
the manager - so a child added tomorrow is extracted the day after with no code
change. Every row carries the child's customer id as `account_id`, and the raw PK is
(platform, account_id, campaign_id, date): the same campaign id in two accounts can
never collide, and every row says which account it came from.

Access level (measured 2026-09-14): `list_accessible_customers` works, everything
else returns CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION. Since 2026-09-09 Google grants
the access level to the GOOGLE CLOUD PROJECT that owns the credentials (here the
service account's project, ecomovers-datawarehouse), not to the developer token - the
token is still sent but ignored. The fix is "Apply for access" on
console.cloud.google.com/google/ads-apis/overview, not the manager's API Center. The
client raises that error as-is; there is nothing to retry.
"""

from __future__ import annotations

import base64
import json
import time
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LOG_PATH = REPO_ROOT / "scripts" / "api_call_log.jsonl"

PLATFORM = "google_ads"
SCOPES = ["https://www.googleapis.com/auth/adwords"]

# The query behind raw_google_ads.campaign_daily - one row per (campaign, day).
# cost_micros is cost x 1,000,000 and is landed AS IS; staging divides.
# advertising_channel_type is promoted because it separates Google Ads from Local
# Services Ads, which are distinct families in the CRM (`Google Ads` vs `Google LSA`).
CAMPAIGN_DAILY_GAQL = """
SELECT
  customer.id,
  customer.descriptive_name,
  customer.currency_code,
  customer.time_zone,
  segments.date,
  campaign.id,
  campaign.name,
  campaign.status,
  campaign.advertising_channel_type,
  campaign.advertising_channel_sub_type,
  campaign.bidding_strategy_type,
  metrics.cost_micros,
  metrics.impressions,
  metrics.clicks,
  metrics.conversions,
  metrics.conversions_value,
  metrics.all_conversions
FROM campaign
WHERE segments.date BETWEEN '{date_from}' AND '{date_to}'
"""

# The account tree under the manager. `level` 0 is the manager itself.
CUSTOMER_CLIENT_GAQL = """
SELECT
  customer_client.id,
  customer_client.descriptive_name,
  customer_client.manager,
  customer_client.level,
  customer_client.status,
  customer_client.currency_code,
  customer_client.time_zone,
  customer_client.test_account
FROM customer_client
"""

_RETRYABLE = ("RESOURCE_EXHAUSTED", "UNAVAILABLE", "DEADLINE_EXCEEDED", "INTERNAL")


def load_env() -> dict[str, str]:
    """Same parser and same quote-stripping rule as sm_pipeline.client.load_env."""
    from sm_pipeline.client import load_env as _load

    return _load()


class BudgetExceeded(RuntimeError):
    pass


class GoogleAds:
    def __init__(self, budget: int = 50, max_retries: int = 4,
                 login_customer_id: str | None = None):
        env = load_env()
        try:
            dev_token = env["GOOGLE_ADS_DEVELOPER_TOKEN"]
            key_b64 = env["GOOGLE_ADS_SERVICE_ACCOUNT_JSON_B64"]
        except KeyError as exc:
            raise SystemExit(f"missing {exc} in .env - see marketing_ads_integration_guide.md 2.1")
        info = json.loads(base64.b64decode(key_b64))

        from google.ads.googleads.client import GoogleAdsClient
        from google.oauth2 import service_account

        creds = service_account.Credentials.from_service_account_info(info, scopes=SCOPES)
        self.login_customer_id = _digits(
            login_customer_id or env.get("GOOGLE_ADS_LOGIN_CUSTOMER_ID") or "")
        self.client = GoogleAdsClient(
            credentials=creds,
            developer_token=dev_token,
            login_customer_id=self.login_customer_id or None,
        )
        self.service_account_email = info.get("client_email")
        self.budget = budget
        self.max_retries = max_retries
        self.calls_made = 0

    # -- ledger --------------------------------------------------------------

    def _log(self, method: str, customer_id: str | None, params: dict, status: str,
             rows: int | None, ms: int):
        record = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": PLATFORM,
            "login_customer_id": self.login_customer_id,
            "customer_id": customer_id,
            "method": method,
            "params": params,
            "status": status,
            "rows": rows,
            "ms": ms,
        }
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def _call(self, method: str, customer_id: str | None, params: dict, fn):
        """Run `fn()` under the budget, the ledger and the retry policy."""
        from google.ads.googleads.errors import GoogleAdsException

        for attempt in range(self.max_retries + 1):
            if self.calls_made >= self.budget:
                raise BudgetExceeded(f"session budget of {self.budget} calls reached")
            t0 = time.monotonic()
            self.calls_made += 1
            try:
                result = fn()
                rows = len(result) if isinstance(result, list) else None
                self._log(method, customer_id, params, "OK", rows,
                          int((time.monotonic() - t0) * 1000))
                return result
            except GoogleAdsException as exc:
                codes = [_error_code_name(e) for e in exc.failure.errors]
                self._log(method, customer_id, params,
                          ",".join(codes) or "GoogleAdsException",
                          None, int((time.monotonic() - t0) * 1000))
                retryable = any(c in _RETRYABLE for c in codes) or any(
                    "QUOTA" in c or "RATE" in c for c in codes)
                if not retryable or attempt == self.max_retries:
                    raise
            except Exception as exc:  # gRPC transport errors surface as plain exceptions
                name = type(exc).__name__
                self._log(method, customer_id, params, name, None,
                          int((time.monotonic() - t0) * 1000))
                if attempt == self.max_retries or not any(k in str(exc) for k in _RETRYABLE):
                    raise
            time.sleep(min(60, 5 * 2 ** attempt))

    # -- reads ---------------------------------------------------------------

    def accessible_customers(self) -> list[str]:
        """Customer ids the credentials can see directly. Normally just the manager."""
        svc = self.client.get_service("CustomerService")

        def fn():
            return [_digits(r) for r in svc.list_accessible_customers().resource_names]

        return self._call("CustomerService.ListAccessibleCustomers", None, {}, fn)

    def account_tree(self, manager_id: str | None = None) -> list[dict]:
        """Every account under the manager, the manager itself included (level 0)."""
        manager_id = _digits(manager_id or self.login_customer_id)
        if not manager_id:
            raise SystemExit("GOOGLE_ADS_LOGIN_CUSTOMER_ID is empty - set it to the manager id")
        ga = self.client.get_service("GoogleAdsService")

        def fn():
            out = []
            for row in ga.search(customer_id=manager_id, query=CUSTOMER_CLIENT_GAQL):
                c = row.customer_client
                out.append({
                    "platform": PLATFORM,
                    "account_id": str(c.id),
                    "account_name": c.descriptive_name,
                    "is_manager": bool(c.manager),
                    "level": int(c.level),
                    "status": _enum_name(c, "status"),
                    "currency_code": c.currency_code,
                    "time_zone": c.time_zone,
                    "is_test_account": bool(c.test_account),
                    "manager_id": manager_id,
                })
            return out

        return self._call("GoogleAdsService.Search", manager_id,
                          {"resource": "customer_client"}, fn)

    def child_accounts(self, manager_id: str | None = None) -> list[dict]:
        """Non-manager, ENABLED accounts under the manager - the ones that hold campaigns."""
        return [a for a in self.account_tree(manager_id)
                if not a["is_manager"] and a["status"] == "ENABLED"]

    def campaign_daily(self, customer_id: str, date_from: str, date_to: str) -> list[dict]:
        """One row per (campaign, day) for one child account. Dates are 'YYYY-MM-DD'
        in the ACCOUNT's time zone - Google reports by the account's day, not UTC."""
        customer_id = _digits(customer_id)
        ga = self.client.get_service("GoogleAdsService")
        query = CAMPAIGN_DAILY_GAQL.format(date_from=date_from, date_to=date_to)

        def fn():
            out = []
            for batch in ga.search_stream(customer_id=customer_id, query=query):
                for row in batch.results:
                    out.append(_flatten_campaign_row(row))
            return out

        return self._call("GoogleAdsService.SearchStream", customer_id,
                          {"resource": "campaign", "date_from": date_from,
                           "date_to": date_to}, fn)


def _enum_name(msg, field: str) -> str:
    """Enum field as its NAME ('ENABLED'), not its number.

    With the client's default (use_proto_plus=False, what this repo uses) messages
    are plain protobuf: enum fields come back as ints and the message carries its
    DESCRIPTOR directly. Resolving through the descriptor gives the name for any
    enum field without a per-enum lookup table. Raw should hold the name - `2`
    means nothing to a reader of the table. Falls back to the number rather than
    ever failing an extraction over a label."""
    value = getattr(msg, field)
    if hasattr(value, "name"):
        return value.name
    try:
        enum_type = msg.DESCRIPTOR.fields_by_name[field].enum_type
        return enum_type.values_by_number[int(value)].name
    except Exception:  # noqa: BLE001
        return str(value)

def _digits(s: str) -> str:
    """'customers/123-456-7890' -> '1234567890'. Customer ids are shown with dashes in
    the UI and required without them by the API."""
    return "".join(ch for ch in str(s) if ch.isdigit())


def _error_code_name(err) -> str:
    """The set field of the error_code oneof, e.g. CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION."""
    try:
        which = err.error_code._pb.WhichOneof("error_code")
        return getattr(err.error_code, which).name if which else "UNKNOWN"
    except Exception:  # noqa: BLE001
        return "UNKNOWN"


def _flatten_campaign_row(row) -> dict:
    """Promote the columns raw needs and keep the whole row as `_payload`, so a field
    not promoted today can be read tomorrow without another API call (ELT rule 1)."""
    from google.protobuf.json_format import MessageToDict

    # Plain protobuf (client default): the row IS the message, there is no ._pb.
    payload = MessageToDict(getattr(row, "_pb", row), preserving_proto_field_name=True)
    return {
        "platform": PLATFORM,
        "account_id": str(row.customer.id),
        "account_name": row.customer.descriptive_name,
        "currency": row.customer.currency_code,
        "account_time_zone": row.customer.time_zone,
        "date": row.segments.date,  # 'YYYY-MM-DD', account-local day
        "campaign_id": str(row.campaign.id),
        "campaign_name": row.campaign.name,
        "campaign_status": _enum_name(row.campaign, "status"),
        "advertising_channel_type": _enum_name(row.campaign, "advertising_channel_type"),
        "advertising_channel_sub_type": _enum_name(row.campaign, "advertising_channel_sub_type"),
        "bidding_strategy_type": _enum_name(row.campaign, "bidding_strategy_type"),
        "cost_micros": int(row.metrics.cost_micros),
        "impressions": int(row.metrics.impressions),
        "clicks": int(row.metrics.clicks),
        "conversions": float(row.metrics.conversions),
        "conversions_value": float(row.metrics.conversions_value),
        "all_conversions": float(row.metrics.all_conversions),
        "_payload": json.dumps(payload, separators=(",", ":")),
    }
