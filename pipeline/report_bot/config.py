"""Configuration and secret loading for the report bot.

The split this module enforces is the whole security model:

    instances.yml   which instances exist, where their reports go   -> in the repo
    .env            usernames and passwords                          -> droplet only
    this module     joins them by VARIABLE NAME                      -> never by value

`instances.yml` names the environment variable that holds each credential. It never
holds one. That is what makes the file safe to commit, safe to paste into a ticket,
and safe to show anyone.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import yaml

CONFIG_PATH = Path(__file__).with_name("instances.yml")


class ConfigError(RuntimeError):
    """Raised for a problem an operator must fix before the bot can run."""


@dataclass(frozen=True)
class Instance:
    id: str
    entity_id: str
    label: str
    login_url: str
    deliver_to: str
    username: str

    # Deliberately not a field on the dataclass: a password must not end up in a
    # repr(), a log line, a traceback frame summary, or a crash report. It is fetched
    # at the moment it is typed and never stored on an object that anything prints.
    _password_env: str = ""

    @property
    def password(self) -> str:
        value = os.environ.get(self._password_env)
        if not value:
            raise ConfigError(
                f"instance {self.id!r}: environment variable {self._password_env} is "
                f"empty. Set it in the droplet's .env (chmod 600), never in the repo."
            )
        return value

    def __repr__(self) -> str:  # pragma: no cover - defensive
        # Explicit, so that a stray print or an exception rendering this object can
        # never surface a credential.
        return (
            f"Instance(id={self.id!r}, entity_id={self.entity_id!r}, "
            f"deliver_to={self.deliver_to!r}, username=<redacted>)"
        )


@dataclass(frozen=True)
class Report:
    id: str
    label: str
    expected_filename_contains: str


@dataclass(frozen=True)
class Window:
    """A resolved date range, ready to type into the report's date picker."""

    name: str
    date_from: date
    date_to: date

    def __str__(self) -> str:
        span = (self.date_to - self.date_from).days
        return f"{self.name} [{self.date_from} .. {self.date_to}] ({span} days)"


def _require(mapping: dict, key: str, where: str):
    if key not in mapping or mapping[key] in (None, ""):
        raise ConfigError(f"{where}: missing required key {key!r}")
    return mapping[key]


def load_config(path: Path | None = None) -> dict:
    path = path or CONFIG_PATH
    if not path.exists():
        raise ConfigError(f"config not found: {path}")
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def load_instances(cfg: dict, only: str | None = None) -> list[Instance]:
    """Build the instance list, failing loudly on a missing credential.

    A missing environment variable is an error, never a skip. An instance that is
    silently skipped looks exactly like one that ran and had nothing to do, and that
    is how a company stops receiving reports without anyone noticing.
    """
    raw = cfg.get("instances") or []
    if not raw:
        raise ConfigError("instances.yml declares no instances")

    out: list[Instance] = []
    problems: list[str] = []

    for entry in raw:
        iid = _require(entry, "id", "instances[]")
        if not entry.get("enabled", True):
            continue
        if only and only != "all" and iid != only:
            continue

        user_env = _require(entry, "username_env", f"instance {iid}")
        pass_env = _require(entry, "password_env", f"instance {iid}")
        username = os.environ.get(user_env)

        if not username:
            problems.append(f"  instance {iid!r}: {user_env} is not set")
            continue
        if not os.environ.get(pass_env):
            problems.append(f"  instance {iid!r}: {pass_env} is not set")
            continue

        out.append(
            Instance(
                id=iid,
                entity_id=_require(entry, "entity_id", f"instance {iid}"),
                label=entry.get("label", iid),
                login_url=_require(entry, "login_url", f"instance {iid}"),
                deliver_to=_require(entry, "deliver_to", f"instance {iid}"),
                username=username,
                _password_env=pass_env,
            )
        )

    if problems:
        raise ConfigError(
            "credentials missing from the environment:\n"
            + "\n".join(problems)
            + "\n\nThese live in the droplet's .env (chmod 600). The repo holds only "
            "the variable NAMES, in instances.yml."
        )

    if only and only != "all" and not out:
        raise ConfigError(f"no enabled instance matches {only!r}")

    return out


def load_reports(cfg: dict) -> list[Report]:
    out = []
    for entry in cfg.get("reports") or []:
        if not entry.get("enabled", True):
            continue
        out.append(
            Report(
                id=_require(entry, "id", "reports[]"),
                label=entry.get("label", entry["id"]),
                expected_filename_contains=entry.get("expected_filename_contains", ""),
            )
        )
    if not out:
        raise ConfigError("instances.yml declares no enabled reports")
    return out


def resolve_window(cfg: dict, name: str, today: date | None = None) -> Window:
    """Turn a window name into concrete dates.

    `auto` maps the current local hour through `auto_window`. It exists for running
    the bot by hand; a scheduled job should always pass the window explicitly, so
    that reading the workflow tells you what it does without having to reason about
    what time it will fire.
    """
    today = today or date.today()

    if name == "auto":
        auto = cfg.get("auto_window") or {}
        from datetime import datetime

        hour = datetime.now().hour
        name = "year" if hour in (auto.get("full_scan_hours") or []) else auto.get("default", "recent")

    windows = cfg.get("windows") or {}
    if name not in windows:
        raise ConfigError(
            f"unknown window {name!r}; instances.yml defines {sorted(windows)}"
        )

    spec = windows[name]
    ahead = int(spec.get("to_days_ahead", 0))

    if spec.get("from") == "year_start":
        start = date(today.year, 1, 1)
    elif "from_days_back" in spec:
        start = today - timedelta(days=int(spec["from_days_back"]))
    else:
        raise ConfigError(
            f"window {name!r}: needs either `from: year_start` or `from_days_back`"
        )

    return Window(name=name, date_from=start, date_to=today + timedelta(days=ahead))
