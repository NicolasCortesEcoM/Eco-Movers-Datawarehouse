-- 32_report_ingest_errors.sql - deadletter for the report email ingestion (Path 3).
-- Idempotent. Run once as the DB admin.
--
-- WHY THIS TABLE EXISTS. The n8n IMAP flow resolves two things from every incoming
-- email: which SmartMoving instance it belongs to (from the recipient alias) and
-- which report it is (from the subject). Neither may be guessed.
--
-- Quote numbers are unique only WITHIN an instance, so mapping an email to the
-- wrong instance silently attaches a `local` quote to an `ld` opportunity - the
-- highest-severity failure mode in the whole pipeline, and one that produces no
-- error, just quietly wrong data. An unrecognised sender or subject therefore
-- lands here, loudly, instead of being attached to a best guess.
--
-- Anything in this table means a report was NOT ingested. Alert on any row.

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_ingest_errors (
  error_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  received_at     timestamptz NOT NULL DEFAULT now(),
  message_id      text,                    -- RFC-2822 Message-ID, for tracing back to the email
  from_address    text,
  to_address      text,                    -- what we saw; compare against the configured aliases
  subject         text,
  attachment_name text,
  report_type     text,                    -- resolved type, when the subject matched but something else failed
  error           text NOT NULL,           -- why the email could not be ingested
  raw_headers     jsonb,                   -- full header set, so a new alias/subject can be diagnosed without the mailbox
  resolved_at     timestamptz,             -- set by hand once the underlying cause is fixed
  UNIQUE (message_id, error)
);

CREATE INDEX IF NOT EXISTS report_ingest_errors_unresolved_idx
  ON raw_smartmoving.report_ingest_errors (received_at)
  WHERE resolved_at IS NULL;

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE ON raw_smartmoving.report_ingest_errors TO platform_rw;
REVOKE ALL ON raw_smartmoving.report_ingest_errors FROM app_read;
