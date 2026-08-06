-- 20_webhook_events.sql - raw landing for SmartMoving webhooks (Camino 1).
-- Idempotent. Run once as the DB admin after 00_bootstrap.sql.
--
-- Written directly by n8n (NOT dlt): the receiver INSERTs the raw event BEFORE
-- any processing and responds 200, so a later enrichment failure never loses the
-- event. This is our OWN history - SmartMoving keeps only 7 days (sync strategy
-- section 5). append-only + dedupe by hash; a replayed webhook never duplicates.
--
-- SmartMoving webhook payloads carry essentially just the resource id + event
-- type; the full record is fetched afterwards by the enrichment worker
-- (run.py --ids ...). So we store the event envelope, not the business fields.

CREATE TABLE IF NOT EXISTS raw_smartmoving.webhook_events (
  event_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  received_at         timestamptz NOT NULL DEFAULT now(),  -- when n8n captured it (= "observed_at")
  source_instance_id  text        NOT NULL,                -- 'ld' | 'local' (from the secret header / URL)
  entity_id           text        NOT NULL,                -- resolved from source_instance_id
  event_type          text        NOT NULL,                -- e.g. 'opportunity-status-changed'
  resource_id         text,                                -- the opportunity/job/customer id to enrich
  payload             jsonb       NOT NULL,                -- the raw event body, verbatim
  dedupe_hash         text        NOT NULL,                -- sha1(event_type|resource_id|payload) - replay guard
  processed_at        timestamptz,                         -- set by the enrichment worker once handled
  process_attempts    int         NOT NULL DEFAULT 0,
  CONSTRAINT webhook_events_dedupe_uniq UNIQUE (dedupe_hash)
);

-- Worker reads the unprocessed backlog by (instance, resource) to debounce.
CREATE INDEX IF NOT EXISTS webhook_events_unprocessed_idx
  ON raw_smartmoving.webhook_events (source_instance_id, resource_id)
  WHERE processed_at IS NULL;

-- Events whose enrichment keeps failing land here (with the last error) so the
-- main backlog never stalls. Alert on any row.
CREATE TABLE IF NOT EXISTS raw_smartmoving.webhook_events_deadletter (
  event_id            bigint      PRIMARY KEY,             -- mirrors webhook_events.event_id
  received_at         timestamptz NOT NULL,
  source_instance_id  text        NOT NULL,
  entity_id           text        NOT NULL,
  event_type          text        NOT NULL,
  resource_id         text,
  payload             jsonb       NOT NULL,
  failed_at           timestamptz NOT NULL DEFAULT now(),
  last_error          text
);

-- raw is platform-only; consumers never read it (CLAUDE.md rule 6).
GRANT INSERT, SELECT, UPDATE ON raw_smartmoving.webhook_events TO platform_rw;
GRANT INSERT, SELECT ON raw_smartmoving.webhook_events_deadletter TO platform_rw;
REVOKE ALL ON raw_smartmoving.webhook_events, raw_smartmoving.webhook_events_deadletter FROM app_read;
