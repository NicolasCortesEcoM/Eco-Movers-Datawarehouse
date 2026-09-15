"""Microsoft Advertising (Bing Ads) API client - the only way this repository talks
to Microsoft Advertising. Same obligations as google_ads.py and sm_pipeline/client.py:

- Credentials from the repo-root .env only: MICROSOFT_DEVELOPER_TOKEN,
  MICROSOFT_ADS_CLIENT_ID / _CLIENT_SECRET, MICROSOFT_ADS_REFRESH_TOKEN (bootstrapped
  once with scripts/msads_oauth.py). The access token in .env is a convenience; the
  client ALWAYS mints a fresh one from the refresh token at start-up, because access
  tokens live 60 minutes and a scheduled run never knows how old the stored one is.
  Microsoft returns a new refresh token with every refresh; it is written back to
  .env when the file is writable, so the 90-day refresh-token lifetime keeps rolling
  as long as the pipeline runs.
- Every call appended to scripts/api_call_log.jsonl with source="microsoft_ads".
- A per-session call budget. Report generation is Submit + N polls + 1 download per
  chunk; a backfill from 2023 is ~12 chunks, so the default budget of 200 is ample.
- Retry with backoff on 429/5xx; never on 401/403 - a bad token does not get better
  by asking again.

HOW COST IS READ. Microsoft has no GAQL. Daily campaign cost comes from the Reporting
API as an ASYNC report: submit a CampaignPerformanceReportRequest (Aggregation=Daily),
poll until Success, download a zip, parse the CSV inside. The JSON/REST flavour of the
v13 endpoints is used, so no SOAP client and no SDK. One report per (account, date
chunk); the CSV is parsed in memory and never written to disk.

ACCOUNT STRUCTURE. The authorised user belongs to a CUSTOMER (the manager-like
container, `CustomerId`), which holds ad ACCOUNTS. Every row carries the ad account id
as `account_id` and the raw PK is (platform, account_id, campaign_id, date), exactly
as for Google, so a campaign id can never be ambiguous across accounts. Accounts are
discovered on every run (Accounts/Search by user), so a new one is extracted the day
after it is granted.

Money: Microsoft reports `Spend` as a decimal string in the account currency. It is
landed AS TEXT in raw (`spend`), and staging casts to numeric - no float is ever
involved, same intent as Google's cost_micros.
"""

from __future__ import annotations

import csv
import io
import json
import re
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LOG_PATH = REPO_ROOT / "scripts" / "api_call_log.jsonl"
ENV_PATH = REPO_ROOT / ".env"

PLATFORM = "microsoft_ads"
SCOPE = "openid offline_access https://ads.microsoft.com/msads.manage"
TOKEN_URL = "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
CUSTOMER_MGMT = "https://clientcenter.api.bingads.microsoft.com/CustomerManagement/v13"
REPORTING = "https://reporting.api.bingads.microsoft.com/Reporting/v13"

# Columns requested from CampaignPerformanceReportRequest; rows are read by header name.
REPORT_COLUMNS = [
    "TimePeriod", "AccountId", "AccountName", "AccountNumber", "CurrencyCode",
    "CampaignId", "CampaignName", "CampaignStatus", "CampaignType",
    "Spend", "Impressions", "Clicks", "Conversions",
    "Revenue", "AllConversions",
]

_RETRYABLE_HTTP = (429, 500, 502, 503, 504)


def load_env() -> dict[str, str]:
    from sm_pipeline.client import load_env as _load

    return _load()


class BudgetExceeded(RuntimeError):
    pass


class MicrosoftAds:
    def __init__(self, budget: int = 200, max_retries: int = 4, poll_seconds: int = 5):
        env = load_env()
        try:
            self.developer_token = env["MICROSOFT_DEVELOPER_TOKEN"]
            self.client_id = env["MICROSOFT_ADS_CLIENT_ID"]
            self.client_secret = env["MICROSOFT_ADS_CLIENT_SECRET"]
            self.refresh_token = env["MICROSOFT_ADS_REFRESH_TOKEN"]
        except KeyError as exc:
            raise SystemExit(f"missing {exc} in .env - run scripts/msads_oauth.py first")
        self.tenant = env.get("MICROSOFT_ADS_TENANT") or "common"
        self.budget = budget
        self.max_retries = max_retries
        self.poll_seconds = poll_seconds
        self.calls_made = 0
        self.access_token: str | None = None
        self.customer_id: str | None = None
        self.user_id: str | None = None
        self.user_name: str | None = None
        self._refresh_access_token()
        self._whoami()

    # -- ledger --------------------------------------------------------------

    def _log(self, method: str, account_id: str | None, params: dict, status: str,
             rows: int | None, ms: int):
        record = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": PLATFORM,
            "customer_id": self.customer_id,
            "account_id": account_id,
            "method": method,
            "params": params,
            "status": status,
            "rows": rows,
            "ms": ms,
        }
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def _post(self, method: str, url: str, body: dict, account_id: str | None = None,
              params: dict | None = None) -> dict:
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "DeveloperToken": self.developer_token,
            "Content-Type": "application/json",
        }
        if self.customer_id:
            headers["CustomerId"] = self.customer_id
        if account_id:
            headers["CustomerAccountId"] = account_id
        for attempt in range(self.max_retries + 1):
            if self.calls_made >= self.budget:
                raise BudgetExceeded(f"session budget of {self.budget} calls reached")
            t0 = time.monotonic()
            self.calls_made += 1
            try:
                r = requests.post(url, headers=headers, json=body, timeout=120)
            except requests.RequestException as exc:
                self._log(method, account_id, params or {}, type(exc).__name__, None,
                          int((time.monotonic() - t0) * 1000))
                if attempt == self.max_retries:
                    raise
                time.sleep(min(60, 5 * 2 ** attempt))
                continue
            ms = int((time.monotonic() - t0) * 1000)
            if r.status_code == 200:
                self._log(method, account_id, params or {}, "OK", None, ms)
                return r.json()
            self._log(method, account_id, params or {}, f"HTTP {r.status_code}", None, ms)
            if r.status_code not in _RETRYABLE_HTTP or attempt == self.max_retries:
                raise RuntimeError(f"{method} -> HTTP {r.status_code}: {r.text[:400]}")
            time.sleep(min(60, 5 * 2 ** attempt))
        raise AssertionError("unreachable")

    # -- auth ----------------------------------------------------------------

    def _refresh_access_token(self):
        t0 = time.monotonic()
        r = requests.post(TOKEN_URL.format(tenant=self.tenant), data={
            "grant_type": "refresh_token", "client_id": self.client_id,
            "client_secret": self.client_secret, "refresh_token": self.refresh_token,
            "scope": SCOPE,
        }, timeout=30)
        self._log("oauth.refresh", None, {}, "OK" if r.ok else f"HTTP {r.status_code}",
                  None, int((time.monotonic() - t0) * 1000))
        if not r.ok:
            raise SystemExit(f"Microsoft token refresh failed ({r.status_code}): "
                             f"{r.json().get('error_description', '')[:300]} - "
                             f"re-run scripts/msads_oauth.py")
        tok = r.json()
        self.access_token = tok["access_token"]
        if tok.get("refresh_token") and tok["refresh_token"] != self.refresh_token:
            self.refresh_token = tok["refresh_token"]
            _rotate_env_refresh_token(self.refresh_token)

    def _whoami(self):
        data = self._post("User.GetUser", f"{CUSTOMER_MGMT}/User/Query", {"UserId": None})
        u = data["User"]
        self.user_id = str(u["Id"])
        self.customer_id = str(u["CustomerId"])
        self.user_name = u.get("UserName")

    # -- reads ---------------------------------------------------------------

    def accounts(self) -> list[dict]:
        """Every ad account the authorised user can see, any status."""
        data = self._post("Accounts.Search", f"{CUSTOMER_MGMT}/Accounts/Search", {
            "Predicates": [{"Field": "UserId", "Operator": "Equals", "Value": self.user_id}],
            "Ordering": None, "PageInfo": {"Index": 0, "Size": 100},
        })
        return [{
            "platform": PLATFORM,
            "account_id": str(a["Id"]),
            "account_number": a.get("Number"),
            "account_name": a.get("Name"),
            "status": a.get("AccountLifeCycleStatus"),
            "currency_code": a.get("CurrencyCode"),
            "time_zone": a.get("TimeZone"),
            "customer_id": str(a.get("ParentCustomerId") or self.customer_id),
        } for a in data.get("Accounts", [])]

    def active_accounts(self) -> list[dict]:
        return [a for a in self.accounts() if a["status"] == "Active"]

    def campaign_daily(self, account_id: str, date_from: str, date_to: str) -> list[dict]:
        """One row per (campaign, day) for one account, dates 'YYYY-MM-DD' in the
        account's time zone (ReportTimeZone left null = the account's own)."""
        y1, m1, d1 = (int(x) for x in date_from.split("-"))
        y2, m2, d2 = (int(x) for x in date_to.split("-"))
        body = {"ReportRequest": {
            "Type": "CampaignPerformanceReportRequest",
            "ExcludeColumnHeaders": False,
            "ExcludeReportFooter": True,
            "ExcludeReportHeader": True,
            "Format": "Csv",
            "FormatVersion": "2.0",
            "ReportName": f"dw campaign daily {account_id} {date_from}..{date_to}",
            "ReturnOnlyCompleteData": False,
            "Aggregation": "Daily",
            "Columns": REPORT_COLUMNS,
            "Scope": {"AccountIds": [int(account_id)]},
            "Time": {
                "CustomDateRangeStart": {"Year": y1, "Month": m1, "Day": d1},
                "CustomDateRangeEnd": {"Year": y2, "Month": m2, "Day": d2},
                "ReportTimeZone": None,
            },
        }}
        params = {"date_from": date_from, "date_to": date_to}
        sub = self._post("Reporting.Submit", f"{REPORTING}/GenerateReport/Submit", body,
                         account_id, params)
        req_id = sub["ReportRequestId"]
        for _ in range(60):
            st = self._post("Reporting.Poll", f"{REPORTING}/GenerateReport/Poll",
                            {"ReportRequestId": req_id}, account_id, params)
            status = st["ReportRequestStatus"]
            if status["Status"] == "Success":
                url = status.get("ReportDownloadUrl")
                return self._download(url, account_id, params) if url else []
            if status["Status"] == "Error":
                raise RuntimeError(f"report {req_id} failed for account {account_id} {params}")
            time.sleep(self.poll_seconds)
        raise RuntimeError(f"report {req_id} still pending after polling - account {account_id}")

    def _download(self, url: str, account_id: str, params: dict) -> list[dict]:
        t0 = time.monotonic()
        self.calls_made += 1
        r = requests.get(url, timeout=300)
        r.raise_for_status()
        rows = _parse_report_zip(r.content)
        self._log("Reporting.Download", account_id, params, "OK", len(rows),
                  int((time.monotonic() - t0) * 1000))
        return rows


def _rotate_env_refresh_token(new_token: str) -> None:
    """Best effort: keep .env's refresh token current so the 90-day clock restarts."""
    try:
        text = ENV_PATH.read_text(encoding="utf-8")
        if re.search(r"^MICROSOFT_ADS_REFRESH_TOKEN=", text, flags=re.M):
            text = re.sub(r"^MICROSOFT_ADS_REFRESH_TOKEN=.*$",
                          f"MICROSOFT_ADS_REFRESH_TOKEN={new_token}", text, flags=re.M)
            ENV_PATH.write_text(text, encoding="utf-8")
    except OSError:
        pass


def _parse_report_zip(content: bytes) -> list[dict]:
    """The zip holds one CSV. With header/footer excluded the first line is the column
    row. Every column is promoted as a string; the whole row travels as `_payload`."""
    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        names = zf.namelist()
        if not names:
            return []
        text = zf.read(names[0]).decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    out = []
    for rec in reader:
        if not rec.get("TimePeriod") or not rec.get("CampaignId"):
            continue  # footer / blank lines, if any slip through
        out.append({
            "platform": PLATFORM,
            "account_id": rec["AccountId"],
            "account_name": rec.get("AccountName"),
            "account_number": rec.get("AccountNumber"),
            "currency": rec.get("CurrencyCode"),
            "date": rec["TimePeriod"],  # 'YYYY-MM-DD' (Daily aggregation)
            "campaign_id": rec["CampaignId"],
            "campaign_name": rec.get("CampaignName"),
            "campaign_status": rec.get("CampaignStatus"),
            "campaign_type": rec.get("CampaignType"),
            "spend": rec.get("Spend"),                 # decimal string, cast in staging
            "impressions": int(rec.get("Impressions") or 0),
            "clicks": int(rec.get("Clicks") or 0),
            "conversions": float(rec.get("Conversions") or 0),
            "conversions_value": rec.get("Revenue"),   # decimal string
            "all_conversions": float(rec.get("AllConversions") or 0),
            "_payload": json.dumps(rec, separators=(",", ":")),
        })
    return out
