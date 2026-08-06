-- 30_report_landing.sql - raw landing for SmartMoving Scheduled Reports (Camino 3).
-- Idempotent. Run once as the DB admin after 00_bootstrap.sql.
--
-- Written directly by n8n (NOT dlt): SmartMoving emails the report on a schedule
-- -' n8n IMAP flow parses the xlsx/csv -' INSERTs one row per report row here.
-- Cost in API quota: ZERO. Role (sync strategy section 6): coverage of fields the API
-- does not expose (storage, past book date, ...), zero-quota historical backfill
-- ("All Time" exports), and continuous cross-check against the API-derived marts.
--
-- Design (CLAUDE.md section Data layers, "volatile source -' preserve full payload in
-- JSONB"): each report row lands as `row_data jsonb` verbatim, so a column the
-- vendor renames never breaks ingestion. dbt promotes/types the columns in
-- stg_smartmoving__report_all_jobs; the ground-truth column set lives in the
-- sample exports under smartmoving_scheduble_reports/.
--
-- Precedence (sync strategy section 12.3): `report_generated_at` is the observation
-- time. A late-arriving report with an older report_generated_at must NOT
-- overwrite fresher data - dbt resolves "last observation wins" by that column,
-- never by arrival order. merge on (source_instance_id, report_generated_at,
-- row_key) keeps re-ingesting the same file idempotent.

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_all_jobs (
  source_instance_id   text        NOT NULL,               -- 'ld' | 'local'
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,               -- when SmartMoving generated it (observation time)
  row_key              text        NOT NULL,               -- stable per-row key from the export (e.g. job/quote number)
  row_data             jsonb       NOT NULL,               -- the export row, verbatim (all columns)
  _ingested_at         timestamptz NOT NULL DEFAULT now(), -- when n8n loaded it
  _source_email        text,                               -- message-id / sender, for audit
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_all_jobs_rowkey_idx
  ON raw_smartmoving.report_all_jobs (source_instance_id, row_key);

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE ON raw_smartmoving.report_all_jobs TO platform_rw;
REVOKE ALL ON raw_smartmoving.report_all_jobs FROM app_read;

-- Add further reports (payments, storage-accounts, booked-by-date-booked, ...) as
-- sibling tables following this exact shape when their Camino-3 schedule is set up.
