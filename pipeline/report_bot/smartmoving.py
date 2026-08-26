"""Driving the SmartMoving web UI with Playwright.

Everything that touches a selector lives in this module and nowhere else. When
SmartMoving redesigns a screen, this is the only file that changes.

WHAT THIS MODULE DOES NOT DO
----------------------------
It does not download the report, parse it, or write a single row. It fills in the
"send results to" field and clicks Run Report, which makes SmartMoving email the
file. `report_ingest` then does what it already does for the other three reports -
see README.md for why splitting it this way is the point rather than a shortcut.
"""

from __future__ import annotations

import logging
import re
from contextlib import contextmanager
from pathlib import Path

from .config import Instance, Report, Window

log = logging.getLogger(__name__)

# SmartMoving's date inputs render M/D/YYYY with no leading zeros. Kept as one
# helper so a locale change is a single edit rather than a hunt through call sites.
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
          "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

DEFAULT_TIMEOUT_MS = 45_000

# --- Selectors -------------------------------------------------------------
# The one place in the codebase that knows what SmartMoving's DOM looks like.
#
# RUN_SEL is a generated test id, not a readable one. It is the most likely thing
# on this list to change without warning, and a changed id makes the click silently
# target nothing - which is why request_email_delivery waits for the button to be
# enabled rather than assuming it exists.
LOGIN_EMAIL_SEL = "#emailAddress"
LOGIN_PASS_SEL = "#password"
LOGIN_SUBMIT_SEL = 'button[data-test-id="sign-in-btn"]'

START_SEL = 'input[formcontrolname="jobDateRangeStart"]'
END_SEL = 'input[formcontrolname="jobDateRangeEnd"]'
EMAIL_SEL = '[data-test-id="sendResultsTo"]'
RUN_SEL = 'button[data-test-id="x4y9tu7gjb"]'

PROFILE_ICON_SEL = '[data-test-id="profileMenuInitialsIcon"]'
PROFILE_NAV_SEL = '[data-test-id="profileMenuNav"]'
LOGOUT_SEL = '[data-test-id="profileMenuLogOut"] a'

LOGGED_OUT_URL_RE = re.compile(r"/(logout|login|sign-?in)")
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


class BrowserStepFailed(RuntimeError):
    """A step against the SmartMoving UI did not do what it was supposed to."""


@contextmanager
def browser_session(headless: bool = True):
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
                # default shared-memory size is larger than it is given here.
                "--disable-dev-shm-usage",
                "--no-sandbox",
            ],
        )
        try:
            yield browser
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


def _mdy(d) -> str:
    """The format the input displays: M/D/YYYY, no leading zeros."""
    return f"{d.month}/{d.day}/{d.year}"


def _mask_email(value: str) -> str:
    """`nicolas@example.com` -> `n***@example.com`. Enough to tell accounts apart in
    a log without writing the whole address into it."""
    if "@" not in value:
        return "<redacted>"
    local, _, domain = value.partition("@")
    return f"{local[:1]}***@{domain}"


# ---------------------------------------------------------------------------
# The steps that touch the interface.
#
# Separate functions rather than one long flow, because when a screen changes it is
# always exactly one of them that breaks, and a stack trace should say which.
# ---------------------------------------------------------------------------


def login(page, instance: Instance) -> None:
    """Authenticate as this instance's user.

    NEVER log, screenshot, or include `instance.password` in an error. It is read
    from the environment at the moment it is typed and is not held on any object
    that something might print.
    """
    log.info("[%s] logging in as %s", instance.id, _mask_email(instance.username))
    page.goto(instance.base_url, wait_until="domcontentloaded")

    page.wait_for_selector(LOGIN_EMAIL_SEL, timeout=30_000)
    page.fill(LOGIN_EMAIL_SEL, instance.username)
    page.fill(LOGIN_PASS_SEL, instance.password)
    page.click(LOGIN_SUBMIT_SEL)

    # Assert on leaving the login screen rather than on the click succeeding. A
    # rejected password leaves the page exactly where it was, so without this a
    # failed login looks like a successful one until a later step fails for a
    # confusing reason - or worse, until the previous instance's session is reused.
    try:
        page.wait_for_url(
            lambda url: "smartmoving.com" in url and "login" not in url.lower(),
            timeout=30_000,
        )
    except Exception as exc:
        raise BrowserStepFailed(
            f"[{instance.id}] still on the sign-in screen after submitting. "
            f"Check the credentials in {instance._password_env} and its username "
            f"variable - the password itself is deliberately not shown here."
        ) from exc

    page.wait_for_timeout(2_000)
    log.info("[%s] signed in", instance.id)


def open_report(page, instance: Instance, report: Report) -> None:
    """Navigate straight to the report's own screen.

    Going to the URL rather than clicking through the navigation menu: fewer
    selectors to break, and the menu structure differs between SmartMoving plans.
    """
    url = instance.base_url + report.path
    log.info("[%s] opening %s at %s", instance.id, report.label, url)

    page.goto(url, wait_until="domcontentloaded")
    page.wait_for_selector(START_SEL, timeout=30_000)
    # Angular hydrates the default date values a moment after the inputs exist.
    # Reading them before that returns empty strings and the ordering logic below
    # then picks the wrong branch.
    page.wait_for_timeout(1_500)


def _pick_date(page, selector: str, target, label: str) -> None:
    """Drive one Angular Material datepicker to a specific date."""
    from playwright.sync_api import TimeoutError as PWTimeout

    inp = page.locator(selector)
    inp.scroll_into_view_if_needed()
    inp.click()

    cal = page.locator("mat-datepicker-content").last
    cal.wait_for(state="visible", timeout=10_000)

    # a) Switch to the multi-year view.
    cal.locator(".mat-calendar-period-button").click()
    page.wait_for_timeout(300)

    # b) Page through 24-year blocks until the target year is on screen. The
    #    direction is decided by comparing against the first year shown, so this
    #    works going backwards as well as forwards.
    year = target.year
    found = False
    for _ in range(15):
        # `:text-is()` rather than a has_text regex. Playwright matches a regex
        # against raw textContent, and these cells carry surrounding whitespace, so
        # `^2026$` never matches even when 2026 is plainly on screen. `:text-is()`
        # normalises whitespace and compares exactly - the same thing the month and
        # day lookups below already do.
        cell = cal.locator(
            ".mat-calendar-body-cell"
        ).filter(
            has=page.locator(f'.mat-calendar-body-cell-content:text-is("{year}")')
        )
        if cell.count():
            first = cell.first
            if first.get_attribute("aria-disabled") == "true":
                raise BrowserStepFailed(
                    f"[{label}] {year} is disabled - outside the allowed min/max."
                )
            first.click()
            found = True
            break

        first_shown = int(
            cal.locator(".mat-calendar-body-cell-content").first.inner_text().strip()
        )
        direction = (
            ".mat-calendar-previous-button" if year < first_shown
            else ".mat-calendar-next-button"
        )
        nav = cal.locator(direction)
        if nav.is_disabled():
            raise BrowserStepFailed(
                f"[{label}] cannot navigate to {year}: the arrow is disabled."
            )
        nav.click()
        page.wait_for_timeout(250)

    if not found:
        raise BrowserStepFailed(f"[{label}] year {year} never appeared in the calendar.")
    page.wait_for_timeout(300)

    # c) Month.
    month = MONTHS[target.month - 1]
    month_cell = cal.locator(".mat-calendar-body-cell").filter(
        has=page.locator(f'.mat-calendar-body-cell-content:text-is("{month}")')
    ).first
    if month_cell.get_attribute("aria-disabled") == "true":
        raise BrowserStepFailed(
            f"[{label}] {month} {year} is disabled - outside the allowed min/max."
        )
    month_cell.click()
    page.wait_for_timeout(300)

    # d) Day.
    day_cell = cal.locator(".mat-calendar-body-cell").filter(
        has=page.locator(f'.mat-calendar-body-cell-content:text-is("{target.day}")')
    ).first
    if day_cell.get_attribute("aria-disabled") == "true":
        raise BrowserStepFailed(
            f"[{label}] {_mdy(target)} is disabled. Check the order the two dates "
            f"are being assigned in - the fields constrain each other."
        )
    day_cell.click()

    try:
        cal.wait_for(state="hidden", timeout=5_000)
    except PWTimeout:
        pass

    # e) Read it back. A datepicker that silently rejects a value produces a report
    #    for the wrong period, which lands successfully and is wrong in a way
    #    nothing downstream can detect.
    got = inp.input_value().strip()
    if got != _mdy(target):
        raise BrowserStepFailed(
            f'[{label}] expected "{_mdy(target)}" but the field holds "{got}".'
        )
    log.info("   %s: %s", label, got)


def set_date_range(page, window: Window) -> None:
    """Set the report's date range.

    THE TWO FIELDS CONSTRAIN EACH OTHER. The start field's `max` follows the end
    field, and the end field's `min` follows the start. If the new start is later
    than the end currently on screen, every day in the start calendar is disabled
    and the step fails for a reason that looks nothing like the cause.

    So the order is decided by reading what the end field currently holds, rather
    than fixed.
    """
    from datetime import datetime

    log.info("setting range %s", window)

    raw_end = page.locator(END_SEL).input_value().strip()
    try:
        current_end = datetime.strptime(raw_end, "%m/%d/%Y").date()
    except ValueError:
        current_end = None

    if current_end and window.date_from > current_end:
        _pick_date(page, END_SEL, window.date_to, "end date")
        _pick_date(page, START_SEL, window.date_from, "start date")
    else:
        _pick_date(page, START_SEL, window.date_from, "start date")
        _pick_date(page, END_SEL, window.date_to, "end date")


def request_email_delivery(page, instance: Instance, report: Report) -> None:
    """Ask SmartMoving to email the report to this instance's reporting mailbox.

    The recipient is what tells `report_ingest` which instance the file belongs to.
    Sending an `ld` report to the `local` mailbox does not raise an error anywhere -
    it attaches ld quote numbers to local opportunities, and the numbers are wrong
    from then on. Hence the read-back below.
    """
    from playwright.sync_api import TimeoutError as PWTimeout

    if not EMAIL_RE.match(instance.deliver_to):
        raise BrowserStepFailed(
            f"[{instance.id}] deliver_to {instance.deliver_to!r} is not a valid "
            f"address. Angular disables Run Report on an invalid one, so the click "
            f"would never fire. Fix it in instances.yml."
        )

    log.info("[%s] requesting delivery to %s", instance.id, instance.deliver_to)

    email = page.locator(EMAIL_SEL)
    email.scroll_into_view_if_needed()
    default_email = email.input_value()
    email.click()
    email.fill("")
    # Typed rather than filled: Angular's validators listen to key events, and a
    # value set in one shot leaves the form model untouched and the button disabled.
    email.press_sequentially(instance.deliver_to, delay=30)
    email.blur()

    final_email = email.input_value().strip()
    if final_email != instance.deliver_to:
        raise BrowserStepFailed(
            f'[{instance.id}] recipient did not stick: "{final_email}" '
            f'(expected "{instance.deliver_to}").'
        )
    if email.evaluate("el => el.classList.contains('ng-invalid')"):
        raise BrowserStepFailed(
            f'[{instance.id}] Angular marked "{instance.deliver_to}" invalid.'
        )
    log.info("   recipient: %s -> %s", default_email or "(empty)", final_email)

    # Wait for the button to become enabled rather than assuming it is. A disabled
    # button swallows the click silently, and the failure would only surface hours
    # later as a report that never arrived.
    try:
        page.wait_for_function(
            "sel => { const b = document.querySelector(sel); return b && !b.disabled; }",
            arg=RUN_SEL,
            timeout=10_000,
        )
    except PWTimeout as exc:
        raise BrowserStepFailed(
            f"[{instance.id}] Run Report is still disabled: some field on the form "
            f"is invalid."
        ) from exc

    page.locator(RUN_SEL).click()
    page.wait_for_timeout(6_000)
    log.info("[%s] %s queued for delivery", instance.id, report.label)


def logout(page, instance: Instance) -> None:
    """End the session.

    Best-effort by design: the report has already been queued by this point, and
    failing the whole run over a sign-out link would throw away work that succeeded.

    This is safe to be lenient about ONLY because every instance gets its own
    browser context - see run_report_for_instance. Cookies cannot leak between
    instances whether or not this succeeds. Without that isolation a silent logout
    failure would attribute the next instance's report to the wrong company, which
    is exactly the class of silent wrongness this project guards against.
    """
    try:
        nav = page.locator(PROFILE_NAV_SEL)
        already_open = "open" in (nav.get_attribute("class") or "")
        if not already_open:
            page.locator(PROFILE_ICON_SEL).click()
            page.wait_for_timeout(600)

        link = page.locator(LOGOUT_SEL)
        link.wait_for(state="visible", timeout=5_000)
        link.click()
        page.wait_for_url(LOGGED_OUT_URL_RE, timeout=15_000)
        page.wait_for_timeout(1_000)
        log.info("[%s] signed out", instance.id)
    except Exception as exc:
        log.warning(
            "[%s] could not sign out (%s). The context is discarded anyway, so the "
            "next instance still starts clean.", instance.id, exc,
        )


def run_report_for_instance(
    browser,
    instance: Instance,
    report: Report,
    window: Window,
    run_dir: Path,
) -> None:
    """The whole flow for one instance, in its own isolated browser context.

    A FRESH CONTEXT PER INSTANCE is the safety property that matters here. Contexts
    do not share cookies or storage, so instance B cannot inherit instance A's
    session no matter what happened during A's sign-out. With two instances running
    back to back, that inheritance would silently file one company's report under
    the other, and nothing downstream could tell.
    """
    context = browser.new_context(viewport={"width": 1600, "height": 1000})
    context.set_default_timeout(DEFAULT_TIMEOUT_MS)
    page = context.new_page()
    try:
        login(page, instance)
        open_report(page, instance, report)
        set_date_range(page, window)
        request_email_delivery(page, instance, report)
        logout(page, instance)
        log.info("[%s] %s requested for %s", instance.id, report.label, window)
    except Exception as exc:
        screenshot_on_failure(page, run_dir, f"{instance.id}_{report.id}_failure")
        # Still try to sign out, so a failed run does not leave a live session on
        # SmartMoving's side.
        logout(page, instance)
        if isinstance(exc, BrowserStepFailed):
            raise
        raise BrowserStepFailed(f"[{instance.id}] {report.label}: {exc}") from exc
    finally:
        context.close()
