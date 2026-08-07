# `report_ingest` - node configuration

Exact configuration for the n8n workflow `report_ingest` (id `3NRvDchKPT5RK4tn`), kept
under version control so the flow can be rebuilt without archaeology.

**Status: applied and verified end-to-end on 2026-08-07.** A real Lead Status email
landed 4,801 rows against 4,801 expected. See `IMPLEMENTATION_STATUS.md` for the
full post-run database audit. The paste-ready node JSON is in
[`n8n_report_ingest_nodes.json`](n8n_report_ingest_nodes.json).

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

```
Report Mailbox (IMAP)
  -> Resolve Report Metadata            (Code)
  -> Recognised Report?                 (IF)
       true  -> Download Report File    (HTTP Request)   <-- NEW
             -> Extract Report Rows     (Extract from File)
             -> Build Landing Rows      (Code)
             -> Land Report Rows        (Postgres)
             -> Verify Landed Row Count (Postgres)       <-- NEW
             -> Assert Row Count Matches (Code)          <-- NEW
       false -> Log Ingest Error        (Postgres)
             -> Alert Unrecognised Report (HTTP Request)
```

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

- **One email per execution is assumed by the verification step.** `Build Landing
  Rows` is pairing-aware and handles several emails correctly, but the two
  verification nodes use `.first()`, so if the IMAP trigger delivers two reports in a
  single execution only the first is verified. Reports are scheduled minutes apart,
  so this is unlikely; revisit if it ever happens.
- **The test alias `reporting@ecomoversmoving.com` maps to `local`.** Remove it from
  `Resolve Report Metadata` once the per-instance aliases are live in SmartMoving.
- **Email cleanup is deliberately not implemented.** `postProcessAction: read` plus
  the `UNSEEN` filter already prevents reprocessing. The email holds the only pointer
  to the download URL (valid 30 days), so deleting it before the row count is
  verified would destroy the ability to retry. If inbox hygiene is wanted later, use
  the Gmail node to archive or label *after* `Assert Row Count Matches` - not before,
  and prefer archiving over permanent deletion.
