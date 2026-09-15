-- 37_pipeline_heartbeat.sql - where the out-of-band liveness check records itself.
-- Idempotent. Run once as the DB admin; safe to replay.
--
-- WHY THIS EXISTS, and why it is not another n8n workflow.
--
-- Every alerting mechanism in this project lives INSIDE an n8n execution: a node
-- throws, and `errorWorkflow` catches the throw. That covers a job that runs and
-- fails. It covers nothing at all when the job does not run:
--
--   * an execution killed by the OOM reaper (this droplet has run at load average 61
--     on 4 cores, and knowingly runs headless Chromium beside Postgres and n8n)
--   * the container restarting mid-run
--   * a schedule trigger that simply never fires
--   * a workflow wedged in a state where it neither errors nor progresses
--
-- The last one is not hypothetical. `report_ingest` collected nothing between
-- 2026-09-07 18:10 PT and a container restart around 03:00 the next morning - nine
-- hours, 39 unread emails, zero errors logged, zero alerts raised. It then recovered
-- on its own. Nobody would have known either way.
--
-- An alert that fires when something throws cannot detect silence. This table is fed
-- by a cron OUTSIDE n8n (scripts/pipeline_heartbeat.py) which asks the opposite
-- question: not "did anything fail?" but "when did each mechanism last succeed?".
--
-- It records EVERY run, not only the bad ones, so "the monitor stopped monitoring" is
-- itself visible - a heartbeat table with no recent heartbeat is the one failure mode
-- a heartbeat cannot report on its own.

CREATE SCHEMA IF NOT EXISTS monitoring;
GRANT USAGE ON SCHEMA monitoring TO platform_rw;

CREATE TABLE IF NOT EXISTS monitoring.pipeline_heartbeat (
  checked_at    timestamptz NOT NULL DEFAULT now(),
  mechanism     text        NOT NULL,   -- 'reports' | 'webhooks' | 'dlt_extraction' | 'dbt_build' | 'ingest_to_build' | 'google_ads' | 'microsoft_ads'
  last_success  timestamptz,            -- NULL = never, which is its own alarm
  age_hours     numeric(10,2),
  threshold_hrs numeric(10,2) NOT NULL,
  is_silent     boolean      NOT NULL,
  detail        text,
  PRIMARY KEY (checked_at, mechanism)
);

CREATE INDEX IF NOT EXISTS pipeline_heartbeat_mechanism_idx
  ON monitoring.pipeline_heartbeat (mechanism, checked_at DESC);

CREATE INDEX IF NOT EXISTS pipeline_heartbeat_silent_idx
  ON monitoring.pipeline_heartbeat (checked_at DESC) WHERE is_silent;

GRANT INSERT, SELECT ON monitoring.pipeline_heartbeat TO platform_rw;

-- Consumers never read monitoring; it is operational, not business data.
REVOKE ALL ON SCHEMA monitoring FROM app_read;

COMMENT ON TABLE monitoring.pipeline_heartbeat IS
  'Out-of-band liveness. Written by scripts/pipeline_heartbeat.py from cron, NOT by '
  'n8n - the point is to notice when n8n is not running at all.';
