// Code node "Resolve Report Metadata" - n8n workflow `report_ingest` (3NRvDchKPT5RK4tn).
// Mode: Run Once for Each Item.
//
// Kept under version control because it is the single point where an email is
// attributed to a SmartMoving instance, and a wrong attribution is silent: quote
// numbers are unique only WITHIN an instance.
//
// CORRECTED 2026-08-07 against a real SmartMoving report email. Two assumptions in
// the first version were wrong:
//
//   1. THE REPORT IS NOT ATTACHED. SmartMoving emails a download link to Azure
//      Blob Storage (content-type is plain text/html, there is no multipart body
//      and no attachment). The file must be fetched over HTTP.
//
//   2. THE SUBJECT IS GENERIC. Every report arrives as "Your SmartMoving Report
//      is Ready!" regardless of type, so the subject identifies nothing. The
//      report type comes from the FILENAME in the download URL
//      (lead-status.xlsx, all-jobs.xlsx, ...), which matches the sample exports
//      in smartmoving_scheduble_reports/.
//
// The body also states "containing N records", which is used downstream to verify
// that the number of rows landed matches what SmartMoving says it sent - a silent
// truncation is otherwise invisible.

const INSTANCE_BY_ALIAS = {
  'ld.reporting@ecomoversmoving.com':    { source_instance_id: 'ld',    entity_id: 'ecomovers' },
  'local.reporting@ecomoversmoving.com': { source_instance_id: 'local', entity_id: 'ecomovers' },

  // TEMPORARY - test alias only.
  // A generic mailbox cannot identify a SmartMoving instance. Remove this entry
  // once the two per-instance aliases are configured in the SmartMoving UI, or a
  // later report sent here is silently attributed to `local`.
  'reporting@ecomoversmoving.com':       { source_instance_id: 'local', entity_id: 'ecomovers' },
};

// Matched against the download URL's filename, NOT the subject.
const REPORTS = [
  { match: 'lead-status',           report_type: 'lead_status',          target_table: 'report_lead_status',          sheet_name: 'data', row_key_field: 'Quote #' },
  { match: 'all-jobs',              report_type: 'all_jobs',             target_table: 'report_all_jobs',             sheet_name: 'jobs', row_key_field: 'Job Id' },
  { match: 'booked-opportunities',  report_type: 'booked_opportunities', target_table: 'report_booked_opportunities', sheet_name: 'data', row_key_field: 'Quote #' },
  { match: 'lost-leads',            report_type: 'lost_leads',           target_table: 'report_lost_leads',           sheet_name: 'data', row_key_field: 'Quote #' },
];

const item = $input.item;
const j = item.json || {};
const headers = j.headers || {};

// Header values arrive with the header name still prefixed
// ("Delivered-To: reporting@..."), so addresses are extracted by pattern rather
// than by trusting the field shape.
function addresses(v) {
  if (!v) return [];
  if (typeof v === 'string') return (v.toLowerCase().match(/[^\s<>,;"]+@[^\s<>,;"]+/g) || []);
  if (Array.isArray(v)) return v.flatMap(addresses);
  if (v.value) return v.value.map(x => String(x.address || '').toLowerCase()).filter(Boolean);
  if (v.text) return addresses(v.text);
  return [];
}

// The same address legitimately appears in several of these, so dedupe - otherwise
// to_address reads "x@y.com, x@y.com, x@y.com" and is useless when diagnosing an
// unrecognised recipient from the error table.
const recipients = [...new Set([
  ...addresses(headers['delivered-to']),
  ...addresses(headers['x-original-to']),
  ...addresses(j.to),
  ...addresses(headers['to']),
  ...addresses(j.cc),
])];

const alias = recipients.find(a => INSTANCE_BY_ALIAS[a]) || null;
const instance = alias ? INSTANCE_BY_ALIAS[alias] : null;

const body = String(j.text || '') + ' ' + String(j.html || '');

// The report-exports path segment is what distinguishes the download link from
// the tracking pixel, the logo and the footer links.
const urlMatch = body.match(/https:\/\/[^\s'"<>]*\/report-exports\/[^\s'"<>]+\.(?:xlsx|xls|csv)/i);
const downloadUrl = urlMatch ? urlMatch[0] : null;
const fileName = downloadUrl ? String(downloadUrl.split('/').pop()).toLowerCase() : null;

const report = fileName ? (REPORTS.find(r => fileName.includes(r.match)) || null) : null;

// "Your Lead Status report, containing 4801 records, is ready to download."
const countMatch = body.match(/containing\s+([\d,]+)\s+records/i);
const expectedRecords = countMatch ? parseInt(countMatch[1].replace(/,/g, ''), 10) : null;

const rawDate = j.date || headers['date'] || null;
let generatedAt = null;
if (rawDate) {
  const parsed = new Date(String(rawDate).replace(/^Date:\s*/i, ''));
  if (!isNaN(parsed.getTime())) generatedAt = parsed.toISOString();
}

const problems = [];
if (!instance)    problems.push('unrecognised recipient alias; saw [' + recipients.join(', ') + ']');
if (!downloadUrl) problems.push('no report download link found in the email body');
if (!report)      problems.push('unrecognised report file: "' + (fileName || 'none') + '"');
if (!generatedAt) problems.push('missing or unparseable Date header');

return {
  json: {
    is_valid: problems.length === 0,
    error: problems.join(' | ') || null,
    matched_alias: alias,
    source_instance_id: instance ? instance.source_instance_id : null,
    entity_id: instance ? instance.entity_id : null,
    report_type: report ? report.report_type : null,
    target_table: report ? report.target_table : null,
    sheet_name: report ? report.sheet_name : null,
    row_key_field: report ? report.row_key_field : null,
    report_generated_at: generatedAt,
    download_url: downloadUrl,
    file_name: fileName,
    expected_records: expectedRecords,
    message_id: j.messageId || headers['message-id'] || null,
    message_uid: j.attributes ? j.attributes.uid : null,
    from_address: (addresses(j.from)[0] || null),
    to_address: recipients.join(', ') || null,
    subject: String(j.subject || '') || null,
    raw_headers: headers,
  },
};
