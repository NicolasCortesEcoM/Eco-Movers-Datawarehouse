"""Driving the SmartMoving web UI with Playwright.

Everything that touches a selector lives in this module and nowhere else. When
SmartMoving redesigns a screen, this is the only file that changes.

WHAT THIS MODULE DOES NOT DO
----------------------------
It does not download the report, parse it, or write a single row. It clicks the
button that makes SmartMoving email the file, and stops. `report_ingest` then does
what it already does for the other three reports - see README.md for why splitting
it this way is the point rather than a shortcut.
"""

from __future__ import annotations

import logging
from contextlib import contextmanager
from datetime import date
from pathlib import Path

from .config import Instance, Report, Window

log = logging.getLogger(__name__)

# SmartMoving's date fields render US-style. Kept as one constant so a locale change
# is a single edit rather than a hunt through four call sites.
DATE_FORMAT = "%m/%d/%Y"

DEFAULT_TIMEOUT_MS = 45_000


class BrowserStepFailed(RuntimeError):
    """A step against the SmartMoving UI did not do what it was supposed to."""


@contextmanager
def browser_session(headless: bool = True, downloads_dir: Path | None = None):
    """Open a browser and guarantee it closes.

    The guarantee is the reason this is a context manager. A crashed run that leaves
    Chromium resident is not theoretical on this droplet: a load spike here was once
    traced to stray headless-Chrome processes. The browser closes on the way out of
    this block whatever happened inside it.
    """
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=[
                # This box runs Postgres, n8n and dbt builds alongside. Chromium's
                # default shared-memory size is larger than the container gives it.
                "--disable-dev-shm-usage",
                "--no-sandbox",
            ],
        )
        try:
            context = browser.new_context(
                accept_downloads=bool(downloads_dir),
                viewport={"width": 1600, "height": 1000},
            )
            context.set_default_timeout(DEFAULT_TIMEOUT_MS)
            try:
                yield context
            finally:
                context.close()
        finally:
            browser.close()


def screenshot_on_failure(page, run_dir: Path, name: str) -> Path | None:
    """Capture what the page looked like when a step failed.

    A moved selector is close to undebuggable without this, and close to trivial with
    it. Written to the run directory, never into the repository - the repo lives in
    OneDrive and does not want binary noise.
    """
    try:
        run_dir.mkdir(parents=True, exist_ok=True)
        path = run_dir / f"{name}.png"
        page.screenshot(path=str(path), full_page=True)
        log.error("saved failure screenshot: %s", path)
        return path
    except Exception:  # pragma: no cover - diagnostics must never mask the real error
        log.exception("could not capture a failure screenshot")
        return None


# ---------------------------------------------------------------------------
# The four steps that touch the interface.
#
# These are stubs. Filling them in needs one walkthrough of the SmartMoving UI:
# which field takes the username, what the report is called in the navigation, how
# the date picker behaves, and what the "email this report" control is.
#
# They are deliberately separate functions rather than one long flow, because when a
# screen changes it is always exactly one of them that breaks, and a stack trace
# should say which.
# ---------------------------------------------------------------------------


def login(page, instance: Instance) -> None:
    """Authenticate as this instance's user.

    NEVER log, screenshot, or include `instance.password` in an error. It is read
    from the environment at the moment it is typed and is not held on any object
    that something might print.
    """
    log.info("[%s] logging in as %s", instance.id, _mask_email(instance.username))
    page.goto(instance.login_url, wait_until="domcontentloaded")

    raise NotImplementedError(
        "login(): needs the SmartMoving sign-in selectors.\n"
        "  - the username field\n"
        "  - the password field\n"
        "  - the submit control\n"
        "  - one element that only exists AFTER a successful login, to assert on\n"
        "\n"
        "That last one matters most: without it a failed login looks like a "
        "successful one until a later step fails for a confusing reason."
    )


def open_report(page, report: Report) -> None:
    """Navigate to the report's own screen."""
    log.info("opening report %s", report.label)

    raise NotImplementedError(
        "open_report(): needs the navigation path to All Jobs, and an element that "
        "proves the report screen is loaded before dates are typed into it."
    )


def set_date_range(page, window: Window) -> None:
    """Set the report's date range.

    Type into the inputs rather than clicking through the calendar where the UI
    allows it. Clicking a date picker across a year boundary means dozens of
    interactions, each a chance to land on the wrong month; typing is one action with
    a value that can be read back and verified.
    """
    log.info("setting range %s", window)
    _ = (window.date_from.strftime(DATE_FORMAT), window.date_to.strftime(DATE_FORMAT))

    raise NotImplementedError(
        "set_date_range(): needs the from/to inputs, and - importantly - a read-back "
        "assertion that the fields actually hold the dates that were typed. A date "
        "picker that silently rejects a value produces a report for the wrong period, "
        "which lands successfully and is wrong in a way nothing downstream can detect."
    )


def request_email_delivery(page, instance: Instance, report: Report) -> None:
    """Ask SmartMoving to email the report to this instance's reporting mailbox.

    The recipient is what tells `report_ingest` which instance the file belongs to.
    Sending an `ld` report to the `local` mailbox does not raise an error anywhere -
    it attaches ld quote numbers to local opportunities, and the numbers are wrong
    from then on. Assert the recipient before submitting.
    """
    log.info("[%s] requesting delivery to %s", instance.id, instance.deliver_to)

    raise NotImplementedError(
        "request_email_delivery(): needs the export/email control, the recipient "
        "field, and the confirmation the UI shows once the send is queued.\n"
        "\n"
        "Assert on that confirmation. Without it the bot reports success for a click "
        "that did nothing, and the failure surfaces hours later as a report that "
        "never arrived."
    )


def logout(page) -> None:
    """End the session so the next instance starts clean.

    Not optional with several instances in one run: a lingering session means the
    second login silently reuses the first instance's account, and every row that
    follows is attributed to the wrong company.
    """
    log.info("logging out")

    raise NotImplementedError(
        "logout(): needs the sign-out control. Assert the sign-in screen is back."
    )


def run_report_for_instance(
    context,
    instance: Instance,
    report: Report,
    window: Window,
    run_dir: Path,
) -> None:
    """The whole flow for one instance: log in, request, log out."""
    page = context.new_page()
    try:
        login(page, instance)
        open_report(page, report)
        set_date_range(page, window)
        request_email_delivery(page, instance, report)
        logout(page)
        log.info("[%s] %s requested for %s", instance.id, report.label, window)
    except NotImplementedError:
        raise
    except Exception as exc:
        screenshot_on_failure(page, run_dir, f"{instance.id}_{report.id}_failure")
        raise BrowserStepFailed(f"[{instance.id}] {report.label}: {exc}") from exc
    finally:
        page.close()


def _mask_email(value: str) -> str:
    """`nicolas@example.com` -> `n***@example.com`. Enough to tell accounts apart in a
    log without writing the whole address into it."""
    if "@" not in value:
        return "<redacted>"
    local, _, domain = value.partition("@")
    return f"{local[:1]}***@{domain}"
