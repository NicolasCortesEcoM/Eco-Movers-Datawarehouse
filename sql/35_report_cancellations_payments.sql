-- 35_report_cancellations_payments.sql - raw landing for the fifth and sixth
-- SmartMoving Scheduled Reports: Cancellation Details and Payments.
-- Idempotent. Safe to re-run.
--
-- Same contract as every other report table (see sql/30_report_landing.sql for the
-- full rationale): the n8n IMAP flow parses the emailed xlsx and writes one row per
-- report row as `row_data jsonb`, verbatim. API quota cost: ZERO.
--
--
-- WHY CANCELLATIONS. The warehouse has `is_cancelled` and `cancellation_reason` but
-- NO CANCELLATION DATE, so today a cancellation can only be attributed to the cohort
-- its lead belongs to - never to the week it actually happened. This report closes
-- that, and brings two more things nothing else has:
--
--     Quote # | Name | Amount | Reason | Cancelled Date | Service Type | Move Date | Phone | Email
--
--   * `Cancelled Date` -> weekly cancellation counts, per agent, as events
--   * `Amount`         -> revenue lost to cancellation
--   * `Reason`         -> why, in the CRM's own words
--
--
-- WHY PAYMENTS, and the thing to get right before modelling it:
--
--     Quote | Job | Storage Account | Customer Name | Type | Amount | CC Fee
--     | Check / CC # | CC Conf Code | Terminal Id | Merchant Ref | Date | Branch
--     | Custom Payment Description | Payment Category
--
-- A payment can attach to an OPPORTUNITY (Quote), a JOB, or a STORAGE ACCOUNT - and
-- a storage account has no quote number at all. Storage accounts are a third
-- top-level entity alongside opportunities and jobs, not a variant of either.
--
-- So when this is modelled, the payments fact needs a nullable link to each of the
-- three plus a `payment_target` discriminator - the same shape core.opportunity_charges
-- already uses for estimated-vs-actual. Forcing every payment under an opportunity id
-- would silently drop every storage payment.
--
-- Landing it now costs nothing and starts accumulating history before the model
-- exists, which is the whole point of keeping raw dumb.
--
--
-- ROW KEY. Neither report has a natural single-column key:
--   * cancellations - `Quote #` is unique per report generation in practice, and the
--     PK includes report_generated_at, so it is sufficient.
--   * payments - a customer can make several payments on one quote on one day, so
--     `Quote` alone would collide. n8n hashes the whole row when the configured key
--     field is blank or duplicated (`__nokey__<hash>`), which is the correct fallback:
--     two identical rows ARE the same observation.

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_cancellations (
  source_instance_id   text        NOT NULL,               -- 'ld' | 'local'
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,               -- when SmartMoving generated it (observation time)
  row_key              text        NOT NULL,
  row_data             jsonb       NOT NULL,               -- the export row, verbatim
  _ingested_at         timestamptz NOT NULL DEFAULT now(),
  _source_email        text,
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_cancellations_rowkey_idx
  ON raw_smartmoving.report_cancellations (source_instance_id, row_key);

CREATE TABLE IF NOT EXISTS raw_smartmoving.report_payments (
  source_instance_id   text        NOT NULL,
  entity_id            text        NOT NULL,
  report_generated_at  timestamptz NOT NULL,
  row_key              text        NOT NULL,
  row_data             jsonb       NOT NULL,
  _ingested_at         timestamptz NOT NULL DEFAULT now(),
  _source_email        text,
  PRIMARY KEY (source_instance_id, report_generated_at, row_key)
);

CREATE INDEX IF NOT EXISTS report_payments_rowkey_idx
  ON raw_smartmoving.report_payments (source_instance_id, row_key);

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE
  ON raw_smartmoving.report_cancellations, raw_smartmoving.report_payments
  TO platform_rw;
REVOKE ALL
  ON raw_smartmoving.report_cancellations, raw_smartmoving.report_payments
  FROM app_read;
