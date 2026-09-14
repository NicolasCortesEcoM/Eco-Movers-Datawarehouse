# `report_ingest` - node configuration

Exact configuration for the n8n workflow `report_ingest` (id `3NRvDchKPT5RK4tn`), kept
under version control so the flow can be rebuilt without archaeology.

**Status: applied and verified end-to-end on 2026-08-07**, rebuilt on **2026-09-09**
after an out-of-memory crash loop. A real Lead Status email landed 4,801 rows against
4,801 expected; after the rebuild, a payments report landed 524/524 rows in 154 ms. See
`IMPLEMENTATION_STATUS.md` for the full post-run database audit. The paste-ready node
JSON is in [`n8n_report_ingest_nodes.json`](n8n_report_ingest_nodes.json).

## ⚠️ The queue is filtered to the reporting aliases, and blockers are archived

Two rules, and the second exists because the first is not enough.

**1. The Gmail search filters on the recipient alias**, server-side:

```
from:no-reply@smartmoving.com subject:"Report is Ready" in:inbox newer_than:7d
{to:reporting@ecomoversmoving.com to:ld.reporting@ecomoversmoving.com
 to:local.reporting@ecomoversmoving.com to:reporting@ecomovers.com
 to:ld.reporting@ecomovers.com to:local.reporting@ecomovers.com}
```

Gmail's `{...}` is OR. A report someone pulled by hand from the SmartMoving UI arrives
at their own address, is not for the warehouse, and now never costs a download - Gmail
excludes it before n8n sees it. This is also the cheapest possible filter: the work
happens at Google, not in a Code node.

**2. Anything that still fails classification is archived out of the inbox**
(`removeLabels: [INBOX]` - the message stays in All Mail, fully recoverable, NOT
deleted).

That second rule is not defensive programming, it is a bug fix. Because the sweep takes
exactly ONE newest-first email, an email it cannot ingest and does not remove is picked
up again on the next run, forever, and **every older report queues behind it**. On
2026-09-09 an All Jobs report addressed to `nicolas@ecomovers.com` did precisely that:
the sweep matched it every 2 minutes, `Resolve Report Metadata` returned
`is_valid: false, is_noise: true`, the filter dropped it, and the 03:10 PT batch behind
it never landed. Nothing errored and nothing alerted - the executions were green and
took 0.7 s, which reads exactly like "no work to do".

⚠️ The unbounded design did not have this failure mode; the one-email-per-run design
does. Never take one email per run without also guaranteeing it leaves the queue.

## ⚠️ The dbt rebuild runs once per BURST, not once per report

`Any Reports Left?` re-runs the sweep search after the email is trashed. If the inbox
still holds a report, this execution skips `Rebuild dbt now` and the last run of the
burst pays for it once. Measured 2026-09-09: landing a report takes ~2 seconds and the
dbt rebuild ~3 minutes, so a burst of six reports used to cost six full rebuilds and
took 30 minutes to land. It now costs one.

That is what makes the 2-minute sweep affordable: a run that finds nothing costs ~0.7 s,
and one that lands a report without rebuilding costs ~15 s.

The nightly `dbt_build_reports` at 03:30 remains the backstop, so a skipped rebuild is
never a missed rebuild.

## ⚠️ ONE report email per execution. Do not raise the limit.

`Find Unprocessed Reports` is `limit: 1`, and the sweep runs `*/5 * * * *`. Throughput
comes from frequency, not from batch size: 288 runs a day against ~34 reports is ample.

It was unbounded until 2026-09-09, and on 09-08 that meant ~60 emails and ~200,000 rows
in one execution. n8n retains every node's input AND output for the life of a run, and
rows were landed one INSERT at a time, so each report was held in memory five or six
times over. The heap gave out at `Build Landing Rows`; runs took 20-30 minutes before
dying. Because the mailbox cleanup sat at the END of the graph, a crash left every email
in the inbox, so the next sweep collected the same batch plus new arrivals - a loop that
ran for 24 hours with no alert, because a process killed for memory throws nothing.

Three things keep it fixed, and all three matter:

1. **`limit: 1`** - memory is bounded by one xlsx, whatever the backlog.
2. **Set-based landing** - `jsonb_to_recordset` in a single statement, not a query per
   row. The whole graph now runs in under two seconds; only the dbt rebuild takes time.
3. **Cleanup before the rebuild** - the email is trashed as soon as its row count is
   verified, which is the point at which it is provably consumed. A later failure can no
   longer feed the loop.

A useful corollary: with one report per run there is exactly one metadata item, so every
`$('Resolve Report Metadata').item` became `.first()` and the flow no longer depends on
paired-item tracing at all. The *"Paired item data for item from node 'Download Report
File' is unavailable"* error was never the bug - n8n rebuilds a crashed run's node
outputs as stubs with no `pairedItem`, so retrying one always failed there.

## ⚠️ The IMAP trigger is DISABLED

It had not fired an execution in weeks - every run came from the Gmail sweep - and it is
the one entry point that cannot be capped, because an IMAP trigger delivers however many
messages are waiting. The filter below applies only if it is ever re-enabled.

## ⚠️ The IMAP filter is a safety device, not an optimisation

```
["UNSEEN", ["FROM", "no-reply@smartmoving.com"]]
```

**The mailbox this reads is a person's working inbox** - roughly 38,000 messages,
14,500 of them unread - not a dedicated reports account. The design assumed a
dedicated mailbox; the deployment does not have one.

With a bare `["UNSEEN"]`, activating this workflow makes n8n try to parse *every
unread email in that inbox* as a SmartMoving report. On 2026-08-13 that produced 39
junk rows in `report_ingest_errors` and a Slack alert each - Google notifications,
Asana, RingCentral, Paylocity - within minutes. It was caught and reverted quickly;
unrestricted it had 14,500 messages still to work through.

**Never widen this back to a bare `UNSEEN`.** If another report sender is added
later, extend the FROM criteria; do not remove them.

## Two things to know before activating

- **The IMAP trigger will not re-fetch a message it has already fetched**, even if
  that message is still marked unread. So a message that failed downstream (a
  download timeout, say) is not retried by re-activating the workflow - the report
  has to be re-sent from SmartMoving, or the row loaded by hand from the download
  URL, which stays valid for 30 days.
- **The download node needs the box to be responsive.** Its timeout is 120 s with 3
  retries. On 2026-08-13 the droplet was saturated by an unrelated headless-Chrome
  workload (load average 61 on 4 cores) and two report downloads timed out even
  though the Azure blob answered a direct `curl` in 0.8 s.

**Why the flow looks like this.** A real SmartMoving report email (2026-08-07) proved
two assumptions wrong:

1. **The report is not attached.** SmartMoving sends a *download link* to Azure Blob
   Storage. The message is plain `text/html` with no multipart body. Verified: the
   blob is publicly readable (`HTTP 200`, no auth), so the download needs no
   credentials.
2. **The subject is generic** - every report arrives as *"Your SmartMoving Report is
   Ready!"*. The report type comes from the **filename in the download URL**.

The email body also states *"containing N records"*, which gives a free integrity
check against silent truncation.

---

## Flow

Current graph (2026-09-14). The IMAP trigger is still in the workflow but disabled.

```
Sweep every 2 min (Schedule)
  -> Find Unprocessed Reports          (Gmail getAll, limit 1, alias-filtered, in:inbox)
  -> Shape Gmail Like IMAP             (Code)
  -> Resolve Report Metadata           (Code)
  -> Recognised Report?                (IF is_valid)
       true  -> Download Report File   (HTTP Request)
             -> Extract Report Rows    (Extract from File)
             -> Build Landing Rows     (Code, one item per report)
             -> Land Report Rows       (Postgres, one INSERT ... ON CONFLICT DO NOTHING)
             -> Purge Legacy Row Keys  (Postgres, transitional, see AUDIT_PLAN A6)
             -> Collect Reports To Verify
             -> Verify Landed Row Count (Postgres)
             -> Assert Row Count Matches (Code, throws on mismatch)
             -> Collect Emails To Clean -> Find Email In Gmail -> Move Email To Trash
             -> Any Reports Left?      (Gmail getAll, limit 1)
             -> Inbox Drained?         (IF)
                  true  -> Drain Quote Backlog (SSH, flock, 300/instance)
                        -> Rebuild dbt now     (SSH, flock)
                        -> Assert Rebuild Succeeded
                  false -> end (the last run of the burst pays for the tail)
       false -> Drop Hand-Pulled Report Noise (Filter) -> Log Ingest Error -> Alert Unrecognised Report
             -> Find Unusable Email -> Archive Out Of Inbox
```

The sections below describe the three nodes added on 2026-08-07 and are kept for the
field-by-field settings; the surrounding graph has moved on as drawn above.

---

## 1. `Download Report File` - NEW, HTTP Request

Insert between `Recognised Report?` (**true** output) and `Extract Report Rows`.

| Field | Value |
|---|---|
| Method | `GET` |
| URL | `={{ $json.download_url }}` |
| Authentication | None - the blob is public |
| Response > Response Format | **File** |
| Response > Put Output in Field | `data` |
| Options > Timeout | `120000` |
| Settings > Retry On Fail | ON, Max Tries `3`, Wait `3000` ms |

"Put Output in Field: `data`" is what creates the binary property the next node
reads. There is no attachment any more, so the old `attachment_0` is gone.

## 2. `Extract Report Rows` - EDIT

| Field | Value |
|---|---|
| Operation | `Extract From Excel (.xlsx)` |
| Input Binary Field | `data` &nbsp;*(plain text, NOT an expression)* |
| Options > Header Row | ON |
| Options > Include Empty Cells | ON |
| Options > Read As String | ON |
| Options > Sheet Name | `={{ $('Resolve Report Metadata').item.json.sheet_name }}` |

> **The Sheet Name expression must reference the Resolve node, not `$json`.**
> After the HTTP download the item carries binary data and an empty `json`, so
> `{{ $json.sheet_name }}` would resolve to nothing and the extraction would fail or
> read the wrong sheet. This matters: `all-jobs.xlsx` uses sheet `jobs` while every
> other report uses `data`.

`Include Empty Cells` fills blanks with an empty string - xlsx physically omits
empty cells, which would otherwise make `row_data` a different shape row to row.
`Read As String` keeps every value as text, which is what the `rpt_*` dbt cast
macros expect.

## 3. `Verify Landed Row Count` - NEW, Postgres

Insert after `Land Report Rows`.

| Field | Value |
|---|---|
| Operation | `Execute Query` |
| Credential | `Datawarehouse Postgres` |
| **Settings > Execute Once** | **ON** |

> **Execute Once is not optional.** `Land Report Rows` emits one item per row - on
> the test report that is 4,801 items, and without this the verification query runs
> 4,801 times.

**Query:**

```sql
SELECT
  {{ $('Resolve Report Metadata').first().json.expected_records }}::int AS expected_records,
  (SELECT count(*)
     FROM raw_smartmoving.{{ $('Resolve Report Metadata').first().json.target_table }}
    WHERE source_instance_id  = $1
      AND report_generated_at = $2::timestamptz) AS landed_records
```

(Prefix the whole query with `=` so n8n treats it as an expression.)

**Options > Query Parameters:**

```
={{ [$('Resolve Report Metadata').first().json.source_instance_id, $('Resolve Report Metadata').first().json.report_generated_at] }}
```

## 4. `Assert Row Count Matches` - NEW, Code

Mode: **Run Once for All Items**.

```javascript
const r = $input.first().json;
const meta = $('Resolve Report Metadata').first().json;

const expected = (r.expected_records === null || r.expected_records === undefined)
  ? null
  : Number(r.expected_records);
const landed = Number(r.landed_records);

// SmartMoving states the record count in the email body. A mismatch means rows were
// dropped somewhere between the download and the insert. Throwing routes this to
// datawarehouse_error_handler, which alerts on Slack: a truncated report that lands
// quietly is far worse than one that fails loudly, because every downstream number
// silently becomes wrong.
if (expected !== null && landed !== expected) {
  throw new Error(
    'Row count mismatch for ' + meta.report_type + ' / ' + meta.source_instance_id +
    ': SmartMoving reported ' + expected + ' records, ' + landed + ' landed. ' +
    'Do not trust downstream numbers for this report until resolved.'
  );
}

return [{
  json: {
    report_type: meta.report_type,
    source_instance_id: meta.source_instance_id,
    report_generated_at: meta.report_generated_at,
    expected_records: expected,
    landed_records: landed,
    verified: true,
  },
}];
```

---

## Known limitations

- **One unpassable email stalls the whole tail of the flow.** Seen three times
  (AUDIT_PLAN A2, A6, A7). `Assert Row Count Matches` throws, the email stays in the
  inbox, the next sweep picks the same email again, and for as long as that lasts:
  every sweep alerts Slack with the same message, `Inbox Drained?` is never true, so
  neither the quote drain nor the dbt rebuild runs — even though every *other* report
  keeps landing correctly (the sweep is newest-first). Landing is not at risk; freshness
  of `core`/`serving` is. The fix that is NOT yet built: after N consecutive failures on
  the same `rfc822_msgid`, quarantine it — log to `report_ingest_errors`, archive out of
  the inbox — and let the burst finish. Until then, the signal to look for is
  *the same row-count alert repeating every 2 minutes*.
- **Row keys can carry a `#<position>` suffix** (since 2026-09-14). A natural key that
  repeats inside one file — SmartMoving does emit the same `Quote #` twice in a Lead
  Status export — is disambiguated by position so both rows land and the count matches.
  Nothing in dbt joins on `row_key`; the reports join on the `Quote #` inside
  `row_data`.
- ~~One email per execution is assumed by the verification step.~~ **FIXED
  2026-08-13, and it was not the unlikely edge case it was written up as.** When all
  eight scheduled reports send together they arrive together: seven reports were
  processed across five executions, several sharing a run. `Collect Reports To
  Verify` now emits one item per distinct `(instance, target_table,
  report_generated_at)` and the verify/assert pair runs per report rather than
  `.first()`.

  Worth noting how this would have failed: landing was always correct, because
  `Build Landing Rows` is pairing-aware. Only the row-count *check* was skipped. So a
  truncated report would have landed short with nothing failing and no alert - the
  exact failure the check exists to catch.
- ~~The test alias `reporting@ecomoversmoving.com` maps to `local`.~~ **Not a test alias.**
  Confirmed by Nicolas 2026-08-25: `local` reports are scheduled to `reporting@` and
  `ld` reports to `ld.reporting@`. That is the live production mapping, and both
  company domains are accepted.
- ~~Email cleanup is deliberately not implemented.~~ **Superseded.** A processed email is
  moved to Trash (per message, never per thread) right after `Assert Row Count Matches`
  and BEFORE the dbt rebuild; an unusable one is archived out of the inbox. The inbox is
  the queue, so both steps are load-bearing.