-- 31_report_booked_lost.sql - raw landing for two more SmartMoving Scheduled
-- Reports (Camino 3): Booked Opportunities and Lost Leads / Opportunities.
-- Idempotent. Run once as the DB admin after 30_report_landing.sql.
--
-- Same contract as raw_smartmoving.report_all_jobs (see sql/30_report_landing.sql
-- for the full rationale): n8n IMAP flow parses the emailed xlsx/csv -' one row
-- per report row as `row_data jsonb` verbatim. Cost in API quota: ZERO.
--
-- Why these two, alongside All Jobs: they give booked / lost COUNTS as an
-- independent, zero-quota source to cross-check the API-derived sweep and the
-- webhook status ledger (marts.int_opportunity_status_latest). Ground-truth
-- columns live in the sample exports under smartmoving_scheduble_reports/
-- (booked-opportunities-by-*.xlsx, lost-leads-opportunities-details.xlsx).
--
-- merge on (source_instance_id, report_generated_at, row_key) keeps re-ingesting
-- the same file idempotent; report_generated_at is the observation time for
-- "last observation wins" (never arrival order).

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_booked_opportunities (
  source_instance_id   text        NOT NULL,               -- 'ld' | 'local'
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,               -- when SmartMoving generated it (observation time)
  row_key              text        NOT NULL,               -- stable per-row key (e.g. quote/opportunity number)
  row_data             jsonb       NOT NULL,               -- the export row, verbatim (all columns)
  _ingested_at         timestamptz NOT NULL DEFAULT now(),
  _source_email        text,                               -- message-id / sender, for audit
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_booked_opportunities_rowkey_idx
  ON raw_smartmoving.report_booked_opportunities (source_instance_id, row_key);

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_lost_leads (
  source_instance_id   text        NOT NULL,
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,
  row_key              text        NOT NULL,
  row_data             jsonb       NOT NULL,
  _ingested_at         timestamptz NOT NULL DEFAULT now(),
  _source_email        text,
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_lost_leads_rowkey_idx
  ON raw_smartmoving.report_lost_leads (source_instance_id, row_key);

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE
  ON raw_smartmoving.report_booked_opportunities, raw_smartmoving.report_lost_leads
  TO platform_rw;
REVOKE ALL
  ON raw_smartmoving.report_booked_opportunities, raw_smartmoving.report_lost_leads
  FROM app_read;
