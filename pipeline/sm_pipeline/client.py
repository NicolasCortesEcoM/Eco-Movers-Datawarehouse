"""SmartMoving API client - single implementation for exploration and pipeline.

- Reads API keys from the repo-root .env (never hardcode keys).
- Logs every call to scripts/api_call_log.jsonl (quota ledger, one line per request).
- Enforces a per-session call budget so no job can run away with the quota.
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

from .instances import INSTANCES

BASE = "https://api-public.smartmoving.com/v1"
_RETRY_SECS_RE = re.compile(r"try again in (\d+)", re.IGNORECASE)
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LOG_PATH = REPO_ROOT / "scripts" / "api_call_log.jsonl"


def load_env() -> dict[str, str]:
    """Parse the repo-root .env into a dict. Used for API keys and Postgres creds."""
    env = {}
    env_file = REPO_ROOT / ".env"
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip()
    return env


# back-compat alias
_load_env = load_env


class BudgetExceeded(RuntimeError):
    pass


class SmartMoving:
    def __init__(self, instance: str, budget: int = 100, timeout: int = 60,
                 max_retries: int = 5, pace: float = 0.0):
        if instance not in INSTANCES:
            raise ValueError(f"instance must be one of {list(INSTANCES)}")
        self.instance = instance
        self.budget = budget
        self.timeout = timeout
        self.max_retries = max_retries
        self.pace = pace  # seconds to sleep before each call (proactive rate-limit throttle)
        self.calls_made = 0
        key = _load_env()[INSTANCES[instance]["api_key_env"]]
        self.session = requests.Session()
        self.session.headers.update({"x-api-key": key, "Content-Type": "application/json"})

    def _log(self, path: str, params: dict, status: int, rows: int | None, ms: int):
        record = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "instance": self.instance,
            "path": path,
            "params": {k: v for k, v in (params or {}).items()},
            "status": status,
            "rows": rows,
            "ms": ms,
        }
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def _retry_after(self, r) -> int:
        """Seconds to wait before retrying a 429, from the Retry-After header or
        the body's 'Try again in N seconds' message. Falls back to 30s."""
        hdr = r.headers.get("Retry-After")
        if hdr and hdr.isdigit():
            return int(hdr)
        m = _RETRY_SECS_RE.search(r.text or "")
        return int(m.group(1)) + 1 if m else 30

    def get(self, path: str, *, allow_missing: bool = False, **params):
        # SmartMoving enforces a short-window rate limit (429 "Try again in N
        # seconds") on top of the monthly quota - confirmed live 2026-07-22 when a
        # burst of enrichment calls tripped it. 429 is retryable (respect the
        # advised wait); 5xx is retryable with backoff; other 4xx are a hard stop.
        #
        # allow_missing=True turns a 404 into None instead of an exception. Used by
        # enrichment: an `opportunity-deleted` webhook feeds the id straight back to
        # GET /api/opportunities/{id}, and without this one 404 kills the whole run
        # and takes every other id batched into the same --ids call with it.
        for attempt in range(self.max_retries + 1):
            if self.calls_made >= self.budget:
                raise BudgetExceeded(f"session budget of {self.budget} calls reached")
            if self.pace:
                time.sleep(self.pace)  # proactive throttle to stay under the rate limit
            t0 = time.monotonic()
            r = self.session.get(BASE + path, params=params or None, timeout=self.timeout)
            ms = int((time.monotonic() - t0) * 1000)
            self.calls_made += 1
            body = None
            rows = None
            try:
                body = r.json()
                if isinstance(body, list):
                    rows = len(body)
                elif isinstance(body, dict) and "pageResults" in body:
                    rows = len(body["pageResults"])
            except ValueError:
                pass
            self._log(path, params, r.status_code, rows, ms)
            if r.status_code == 429 and attempt < self.max_retries:
                wait = self._retry_after(r)
                print(f"  [rate-limit] {path} - waiting {wait}s (attempt {attempt + 1}/{self.max_retries})")
                time.sleep(wait)
                continue
            if r.status_code >= 500 and attempt < self.max_retries:
                time.sleep(2 ** attempt)  # exponential backoff on transient server errors
                continue
            if r.status_code == 404 and allow_missing:
                return None  # gone at source - caller records a soft-delete marker
            if r.status_code >= 400:
                raise requests.HTTPError(f"{r.status_code} on {path}: {r.text[:300]}", response=r)
            return body

    def paginate(self, path: str, max_pages: int = 50, **params):
        params = dict(params)
        params.setdefault("PageSize", 200)  # server caps at 200 - asking more is silently clamped
        params["Page"] = 1
        pages = 0
        while True:
            body = self.get(path, **params)
            pages += 1
            yield from body["pageResults"]
            if body.get("lastPage") or pages >= max_pages:
                return
            params["Page"] += 1
