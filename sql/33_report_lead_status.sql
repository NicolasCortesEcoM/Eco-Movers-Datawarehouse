-- 33_report_lead_status.sql - raw landing for the Lead Status scheduled report.
-- Idempotent. Run once as the DB admin, after 30_report_landing.sql.
--
-- THIS IS THE MOST IMPORTANT REPORT IN THE SET. Read this before adding others.
--
-- Why it matters more than the rest:
--   * It is keyed on LEAD RECEIVED DATE, so one export returns EVERY lead and
--     opportunity received in a period - won, lost, cancelled, bad, still open.
--     The other reports each show one slice (only booked, only lost); this one is
--     the denominator. Without it you cannot compute a conversion rate.
--   * It carries the authoritative `Status` column: the business outcome, with the
--     lost/cancelled subcategory attached ("Lost price too high",
--     "Cancelled no availability"). That string maps 99% to the dim_status_map seed.
--   * Volume: the sample export is 5,278 rows against 7-106 for the others.
--   * Cost in API quota: ZERO.
--
-- Column ground truth is smartmoving_scheduble_reports/lead-status.xlsx (sheet
-- 'data', 16 columns). Parser hazards measured in that file:
--   * "Service Date" uses '0/0/0' as its null sentinel, not blank.
--   * "Estimated Revenue" is a STRING ('0.00'), not a number.
--   * "Volume/Weight" is ONE combined field ('-- cuft / -- lbs'), dashes = unknown.
--   * "Received at" is 'M/D/YYYY H:MM AM' in the CRM's configured timezone - which
--     is NOT UTC. Convert using dim_instance.crm_timezone.
--   * "Quote #" is a string and is the row_key.
--
-- Same contract as raw_smartmoving.report_all_jobs (see sql/30_report_landing.sql):
-- one row per report row as `row_data jsonb` verbatim, so a column the vendor
-- renames never breaks ingestion. merge on
-- (source_instance_id, report_generated_at, row_key) keeps re-ingesting the same
-- file idempotent; report_generated_at is the observation time for "last
-- observation wins" (never arrival order).

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_lead_status (
  source_instance_id   text        NOT NULL,               -- 'ld' | 'local'
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,               -- when SmartMoving generated it (observation time)
  row_key              text        NOT NULL,               -- the report's "Quote #"
  row_data             jsonb       NOT NULL,               -- the export row, verbatim (all 16 columns)
  _ingested_at         timestamptz NOT NULL DEFAULT now(),
  _source_email        text,                               -- message-id / sender, for audit
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_lead_status_rowkey_idx
  ON raw_smartmoving.report_lead_status (source_instance_id, row_key);

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE ON raw_smartmoving.report_lead_status TO platform_rw;
REVOKE ALL ON raw_smartmoving.report_lead_status FROM app_read;
