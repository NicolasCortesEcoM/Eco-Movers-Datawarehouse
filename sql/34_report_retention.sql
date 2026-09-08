-- 34_report_retention.sql - prune the report landing tables.
-- Idempotent: running it twice is a no-op. Safe to run on every dbt build.
--
-- Policy (crm_sync_contract.md section 9):
--   * Last 10 days  -> keep EVERY generation.
--   * Older         -> keep ONE generation per calendar day.
--   * Flagged `_is_historical_backfill` -> NEVER pruned. See 36_historical_backfill_marker.sql.
--
-- Why this exists at all: six report sends a day at ~4,800 rows is ~29,000 rows a
-- day from Lead Status alone, about 10 million a year. The droplet is at 90% disk.
-- Without pruning, the landing tables outgrow the box before they outgrow their
-- usefulness.
--
-- Why pruning is safe: dbt collapses report rows to the newest observation per
-- (opportunity, source) in the observation layer, so an older intra-day generation
-- contributes nothing analytical once a newer one exists. What is lost is the
-- ability to replay a specific mid-morning snapshot from more than ten days ago -
-- a debugging convenience, not a data asset.
--
-- Why the 10-day window is not zero: when a report lands wrong, the symptom shows
-- up days later in a metric nobody was watching. Ten days of full history is what
-- makes "which generation broke this?" answerable.
--
-- The calendar day is the INSTANCE's day. report_generated_at is a true timestamptz
-- (converted on ingest), so grouping it in UTC would split a Pacific evening send
-- from the morning ones and keep two rows per day instead of one.

DO $$
DECLARE
  tbl          text;
  deleted      bigint;
  total        bigint := 0;
  keep_all_for interval := interval '10 days';
  -- Predicate that exempts a flagged generation. Empty string when the column is
  -- not there yet, so this file does not depend on 36 having run first - the
  -- deploy replays sql/*.sql in lexicographic order and 34 comes first.
  keep_flagged text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'report_lead_status',
    'report_all_jobs',
    'report_booked_opportunities',
    'report_lost_leads'
  ]
  LOOP
    -- Skip tables that have not been created yet, so this runs on a fresh
    -- environment without ordering constraints against 30-33.
    IF to_regclass('raw_smartmoving.' || tbl) IS NULL THEN
      CONTINUE;
    END IF;

    -- A historical backfill is exempt. It is excluded from the ranking as well as
    -- from the DELETE: left in, it would take the rn=1 slot for its day and push a
    -- routine generation into rn>1, deleting the wrong one. See 36 for why these
    -- exist at all.
    SELECT CASE WHEN EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'raw_smartmoving'
                AND table_name   = tbl
                AND column_name  = '_is_historical_backfill')
           THEN ' AND NOT %1$I._is_historical_backfill '
           ELSE ''
           END
      INTO keep_flagged;

    EXECUTE format($f$
      WITH ranked AS (
        SELECT DISTINCT
               source_instance_id,
               report_generated_at,
               row_number() OVER (
                 PARTITION BY
                   source_instance_id,
                   (report_generated_at AT TIME ZONE COALESCE(i.crm_timezone,
                                                              'America/Los_Angeles'))::date
                 ORDER BY report_generated_at DESC
               ) AS rn
          FROM raw_smartmoving.%1$I r
          LEFT JOIN staging.dim_instance i
                 ON i.instance_id = r.source_instance_id
         WHERE r.report_generated_at < now() - %2$L::interval
           %3$s
      )
      DELETE FROM raw_smartmoving.%1$I t
       USING ranked
       WHERE t.source_instance_id  = ranked.source_instance_id
         AND t.report_generated_at = ranked.report_generated_at
         AND ranked.rn > 1
         %4$s
    $f$, tbl, keep_all_for,
         format(keep_flagged, 'r'),
         format(keep_flagged, 't'));

    GET DIAGNOSTICS deleted = ROW_COUNT;
    total := total + deleted;

    IF deleted > 0 THEN
      RAISE NOTICE 'report_retention: pruned % rows from %', deleted, tbl;
    END IF;
  END LOOP;

  RAISE NOTICE 'report_retention: % rows pruned in total', total;
END $$;
