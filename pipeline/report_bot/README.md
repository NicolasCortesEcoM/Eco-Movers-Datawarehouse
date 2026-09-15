# report_bot — making SmartMoving send the reports it will not schedule

A Playwright bot that logs into the SmartMoving **web UI**, opens a report, sets a
date range, and asks SmartMoving to email it.

It exists for one reason: **All Jobs cannot be put on SmartMoving's own schedule**,
so the only way to get it daily is to drive the interface. Every other report is
scheduled in the UI and needs none of this.

---

## The single most important design decision

**This bot does not download, parse, or load anything. It produces zero rows.**

Its entire job is to make an email arrive. From that point the existing
`report_ingest` workflow does what it already does for every natively scheduled report:
resolves the instance from the mailbox, downloads the attachment link, verifies the
row count against the number stated in the email, lands the rows verbatim as `jsonb`,
and rebuilds dbt.

```
report_bot  ──►  SmartMoving emails the report  ──►  report_ingest  ──►  raw ──► dbt
 (clicks)              (vendor does the work)         (already built)
```

Why it matters, concretely:

- **One parser, not two.** A second download path means a second xlsx reader, a
  second set of column assumptions, and two places to fix a vendor rename.
- **One landing contract.** Same primary key, same `ON CONFLICT DO NOTHING`, same
  idempotency. Re-running the bot twice cannot double-count.
- **The row-count check comes free.** SmartMoving states "containing N records" in
  the email body, and `report_ingest` throws when the landed count disagrees. A bot
  that downloaded the file itself would have no such number to check against.
- **A bot failure is contained.** If the bot breaks, an email does not arrive and the
  data is stale. It cannot corrupt anything, because it never writes to the database.

> If you ever find yourself adding a database connection to this package, stop. That
> is the signal the design has drifted.

---

## Where things live, and why

| What | Where | Why there |
|---|---|---|
| The code | `pipeline/report_bot/` | It is extraction, and all extraction lives under `pipeline/`. It is not dlt, so it does not sit inside `sm_pipeline/`. |
| Which instances exist | `instances.yml` **in the repo** | It is configuration, not a secret. It should be reviewed in a diff like anything else. |
| Usernames and passwords | `.env` **on the droplet only**, `chmod 600` | Never in the repository, never in a log, never in a screenshot. |
| The link between them | env-var **names** in `instances.yml` | The config says *which variable holds the password*, never the password. |

That last row is the whole security model. `instances.yml` is safe to commit, safe to
paste into a ticket, safe to show anyone — because it contains no secret, only the
names of the places secrets are kept.

### Adding a company or an instance

Add a block to `instances.yml`, add two variables to the droplet's `.env`. **No code
change.** A company with one instance and a company with six work identically.

```yaml
- id: acme_main
  entity_id: acme
  label: Acme Movers
  username_env: SMARTMOVING_ACME_ACCOUNT   # the NAME of the variable
  password_env: SMARTMOVING_ACME_PASSWORD  # never the value
  deliver_to: reports@acme.example.com
```

The bot refuses to start if a named variable is missing, rather than silently
skipping that instance — a skipped instance looks exactly like a successful run.

---

## How it is scheduled: n8n, not cron

**Recommendation: an n8n schedule that SSHes into the droplet and runs the script**,
exactly like `opps_sweep` and every other extraction workflow.

This is not a preference. Cron has one specific failure mode this project has already
lived through:

> Extraction failed at the load step from 2026-07-22 and reported success the whole
> time. **Seventeen days, no alert.** It was found by accident.

A cron job that fails writes to a log nobody reads. Choosing n8n buys four things
that already exist and would otherwise have to be rebuilt:

1. **`errorWorkflow` → Slack.** A failure reaches a person the same minute.
2. **The exit-code assertion.** The SSH node reports the remote status but does *not*
   fail the workflow on it. The `Assert Exit Code` pattern in
   `deploy/n8n_workflow_migration.md` is what turns that into an alert, and it is
   already written and proven.
3. **One place where every schedule lives.** `crm_sync_contract.md` documents the
   times; n8n runs them. A cron entry on a box is a schedule nobody can find.
4. **Execution history.** What ran, when, what it printed, and a retry button.

The script still runs on the droplet — Playwright needs a real browser and n8n only
sends the command. n8n is the scheduler and the alerting path, not the runtime.

> ⚠️ **Chromium is heavy and this droplet is small** (4 cores, 7 GB, and already
> carrying Postgres, n8n and the dbt builds). Run the browser headless, one instance
> at a time, never in parallel, and keep `--max-old-space-size` modest. A previous
> load spike on this box was traced to stray headless-Chrome processes; the bot must
> always close its browser, including on failure.

### Where it sits in the day

The bot must finish **before** the report emails are expected, so the whole day's
data lands together. `crm_sync_contract.md` section 6 is the authority on the times;
add the bot's row there rather than here.

The full-year run and the rolling runs are the same script with a different window —
see below.

---

## Two windows, because a full year every two hours is waste

| Window | Range | When | Why |
|---|---|---|---|
| `year` | 1 Jan of the current year → *n* days ahead | The first run of the day | Corrects anything that changed in the past, and back-fills a run that was missed. |
| `recent` | 90 days back → *n* days ahead | Every later run | Freshness. Nothing older than 90 days changes often enough to re-pull six times a day. |

Both are defined in `instances.yml`, not in code, so changing them is a config edit.

**The window is passed in explicitly by the scheduler.** `--window auto` exists and
infers from the local hour, but it is for convenience at a terminal — an n8n job
should always state which window it wants, so that reading the workflow tells you
what it does without having to reason about what time it will run.

---

## Failure behaviour

- **One instance failing does not stop the others.** The bot continues to the next
  and exits non-zero at the end, so every instance that *could* run does, and the
  alert still fires.
- **A screenshot is written on failure** to the run directory (never the repo), which
  is the only practical way to debug a selector that moved.
- **Passwords are never logged**, never screenshotted at the moment of entry, and
  never included in an error message.
- **The browser is always closed**, including on an exception, so a crashed run
  cannot leave Chromium resident on the droplet.
- **A blank sign-in page is retried, not failed.** On the droplet the SmartMoving
  app sometimes never paints on a cold load - the screenshot is pure white and
  `#emailAddress` never appears. Seen for `ld` at 10:00 and 13:00 PT on three
  consecutive days (2026-09-12..14) while `local`, seconds later, signed in fine.
  `login()` now reloads up to three times before raising, the same way
  `open_report()` already did. Three blank loads in a row is a real outage and is
  still reported as one.
- **A failed request is not re-requested until the next scheduled run.** The alert
  fires and is correct, but that instance's All Jobs window is simply missed for
  those three hours. Re-run by hand with
  `python -m pipeline.report_bot.run --instance <id> --report all_jobs --window recent`.

---

## Status

**Working, and verified end to end against production on 2026-08-25.**

```
[ld]    logging in as i***@interstate.ecomovers.com
[ld]    signed in
[ld]    opening All Jobs at https://app.smartmoving.com/reports/all-jobs
        start date: 1/1/2026      <- read back from the field, not assumed
        end date:   12/31/2026
        recipient:  info@interstate.ecomovers.com -> ld.reporting@ecomoversmoving.com
[ld]    All Jobs queued for delivery
[ld]    signed out
[local] logging in as p***@sales.ecomovers.com
        ... same, delivered to reporting@ecomoversmoving.com
all 2 request(s) sent.
```

The first request landed through the normal path minutes later: 852 rows in
`raw_smartmoving.report_all_jobs`, zero rows in `report_ingest_errors`. Nothing in
the ingestion side needed changing, which is the whole point of the split.

### The trap this caught immediately

**Every instance's report form defaults to a mailbox `report_ingest` does not read** -
`info@interstate.ecomovers.com` for `ld`, `pedro@sales.ecomovers.com` for `local`.
Left alone, the report is emailed to a person and the warehouse never sees it. That
is why `request_email_delivery` clears the field, types the configured recipient, and
reads it back before clicking Run Report.

### Running on the droplet: no deep link, ever

The report has **no working deep link**, and this cost a debugging session to
establish. Loading `https://app.smartmoving.com/reports/all-jobs` directly always
lands on `/home`. Measured: three attempts, `wait_until="networkidle"`, seconds of
settle time between them, every one bounced. It is a router guard rejecting a cold
load, not a race a longer wait can win.

It appeared to work on a laptop only by accident: **SmartMoving restores the user's
last visited route on sign-in**, and that account happened to be parked on the
report. The first droplet run, whose session was parked elsewhere, failed instantly.

So the bot navigates the way the running app does - push the route onto history and
let Angular's router pick it up from `popstate`. No page load, no guard, no bounce.

### Scheduling

n8n workflow **`report_bot_all_jobs`** (`0fsombzQ1psDwh75`), in the Datawarehouse
folder. Two schedule triggers, each SSHing into the droplet with its window stated
explicitly, both feeding one `Assert Exit Code` node. `errorWorkflow` is
`datawarehouse_error_handler`, so a failure reaches Slack.

`crm_sync_contract.md` section 6 owns the times.

Verified 2026-08-26: manual execution succeeded, `requests_sent: 2`.

### The one selector most likely to break

`RUN_SEL = 'button[data-test-id="x4y9tu7gjb"]'` is a generated id, not a readable
one, so a SmartMoving release can change it without anything looking suspicious. The
failure is loud rather than silent - `request_email_delivery` waits for the button to
become enabled and raises when it does not - but that is the line to check first when
a run starts failing for no apparent reason.
