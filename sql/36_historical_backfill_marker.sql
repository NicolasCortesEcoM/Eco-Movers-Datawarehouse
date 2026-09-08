-- 36_historical_backfill_marker.sql - protect one-time historical loads from retention.
-- Idempotent. Safe to replay on every deploy.
--
-- THE PROBLEM THIS SOLVES, and it had a date on it.
--
-- `34_report_retention.sql` keeps, for anything older than 10 days, ONE generation
-- per instance per calendar day. That is correct while every generation of a report
-- is the same content at a different hour - which is true of the six scheduled sends.
--
-- It is NOT true of a historical backfill. On 2026-09-07 the 2023-2025 exports were
-- requested by hand and all arrived within thirteen minutes of each other, so they
-- carry `report_generated_at` values on the SAME Pacific day while holding DIFFERENT
-- YEARS of business data:
--
--   report_lead_status  local 18:20:12 -> 2024   (14,963 rows)
--   report_lead_status  local 18:22:02 -> 2025   (18,402 rows)
--   report_lead_status  local 18:22:33 -> 2023   (16,887 rows)
--   report_all_jobs     local 18:20:21 -> 2023   (14,900 rows)
--   ... 15 generations in total, 137,101 rows
--
-- On 2026-09-17 the retention pass would have kept one of each group and deleted the
-- rest - silently destroying 2023 and 2024. The row counts would still look healthy
-- because the newest generation survives; only the history would be gone.
--
-- THE FIX: a generation can declare itself exempt. Retention skips anything flagged.
--
-- Why a marker column and not a cleverer rule: the obvious content-based rule
-- ("protect a generation whose data predates the year it was generated") over-fires.
-- Measured on the live warehouse, it also protects ten routine `ld` Booked
-- Opportunities generations, because Long Distance has no 2026 booked date at all -
-- its newest booking is from 2025. A retention rule that quietly protects the wrong
-- thing is the same class of bug as one that quietly deletes the right thing.
--
-- Anything loading a historical export from here on sets this flag at insert time.

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'report_lead_status',
    'report_all_jobs',
    'report_booked_opportunities',
    'report_lost_leads'
  ]
  LOOP
    IF to_regclass('raw_smartmoving.' || tbl) IS NULL THEN
      CONTINUE;
    END IF;

    -- Postgres 11+ records a constant default in the catalogue rather than
    -- rewriting the heap, so this stays metadata-only even on the 785 MB
    -- report_all_jobs.
    EXECUTE format(
      'ALTER TABLE raw_smartmoving.%I
         ADD COLUMN IF NOT EXISTS _is_historical_backfill boolean NOT NULL DEFAULT false',
      tbl);
  END LOOP;
END $$;

COMMENT ON COLUMN raw_smartmoving.report_lead_status._is_historical_backfill IS
  'True when this generation is a one-time export of a past period rather than a '
  'scheduled send. 34_report_retention.sql never prunes a flagged row.';

-- ---------------------------------------------------------------------------
-- Flag the 2026-09-07 backfill.
--
-- Selection is pinned to that load rather than expressed as a general rule, for the
-- reason in the header. Two conditions, both required:
--
--   1. report_generated_at inside the thirteen-minute window the exports arrived in
--      (18:16-18:29 America/Los_Angeles on 2026-09-07). The scheduled sends that day
--      were at 03:0x, 19:2x and 20:0x, so the window cannot catch one by accident.
--   2. The generation holds nothing from 2026, which is what makes it a historical
--      export rather than a cumulative one.
--
-- Re-running only ever sets the same rows, and the `IS NOT TRUE` guard means a replay
-- touches nothing.
--
-- Each statement is ONE aggregate pass over the window plus an indexed update. The
-- first draft expressed the same rule with a correlated NOT EXISTS and ran for over
-- ten minutes on report_lead_status before it was killed: it re-scanned the whole
-- generation once per candidate row.
-- ---------------------------------------------------------------------------

WITH gens AS (
    SELECT source_instance_id, report_generated_at
      FROM raw_smartmoving.report_lead_status
     WHERE report_generated_at >= timestamptz '2026-09-07 18:16:00-07'
       AND report_generated_at <  timestamptz '2026-09-07 18:29:00-07'
     GROUP BY 1, 2
    HAVING max(substring(row_data->>'Received at' from '(\d{4})')::int) < 2026
)
UPDATE raw_smartmoving.report_lead_status t
   SET _is_historical_backfill = true
  FROM gens g
 WHERE t.source_instance_id  = g.source_instance_id
   AND t.report_generated_at = g.report_generated_at
   AND t._is_historical_backfill IS NOT TRUE;

WITH gens AS (
    SELECT source_instance_id, report_generated_at
      FROM raw_smartmoving.report_all_jobs
     WHERE report_generated_at >= timestamptz '2026-09-07 18:16:00-07'
       AND report_generated_at <  timestamptz '2026-09-07 18:29:00-07'
     GROUP BY 1, 2
    HAVING max(substring(row_data->>'Job Date' from '(\d{4})')::int) < 2026
)
UPDATE raw_smartmoving.report_all_jobs t
   SET _is_historical_backfill = true
  FROM gens g
 WHERE t.source_instance_id  = g.source_instance_id
   AND t.report_generated_at = g.report_generated_at
   AND t._is_historical_backfill IS NOT TRUE;

WITH gens AS (
    SELECT source_instance_id, report_generated_at
      FROM raw_smartmoving.report_booked_opportunities
     WHERE report_generated_at >= timestamptz '2026-09-07 18:16:00-07'
       AND report_generated_at <  timestamptz '2026-09-07 18:29:00-07'
     GROUP BY 1, 2
    HAVING max(substring(row_data->>'Booked Date' from '(\d{4})')::int) < 2026
)
UPDATE raw_smartmoving.report_booked_opportunities t
   SET _is_historical_backfill = true
  FROM gens g
 WHERE t.source_instance_id  = g.source_instance_id
   AND t.report_generated_at = g.report_generated_at
   AND t._is_historical_backfill IS NOT TRUE;

WITH gens AS (
    SELECT source_instance_id, report_generated_at
      FROM raw_smartmoving.report_lost_leads
     WHERE report_generated_at >= timestamptz '2026-09-07 18:16:00-07'
       AND report_generated_at <  timestamptz '2026-09-07 18:29:00-07'
     GROUP BY 1, 2
    HAVING max(substring(row_data->>'Date Received' from '(\d{4})')::int) < 2026
)
UPDATE raw_smartmoving.report_lost_leads t
   SET _is_historical_backfill = true
  FROM gens g
 WHERE t.source_instance_id  = g.source_instance_id
   AND t.report_generated_at = g.report_generated_at
   AND t._is_historical_backfill IS NOT TRUE;
