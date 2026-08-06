-- 10_apply_rls.sql - enable Row-Level Security on every core + serving table
-- that has an entity_id column, keyed on the core.entity_access map.
--
-- Run AFTER every `dbt build` (dbt drops/recreates tables, which drops their
-- policies). Idempotent. Run as the table owner (platform_rw) or a superuser.
--
-- Why a loop instead of per-model hooks: a junior maintainer runs one script
-- and every consumer-facing table is secured - no per-model wiring to forget.
-- platform_rw owns these tables and bypasses RLS by design; app_read (and any
-- per-team consumer role) is filtered to its allowed entity_ids.

-- Grants: app_read reads serving + core only (hybrid access, decisions/0003).
-- Needed when dbt runs as a superuser locally (objects it creates are not covered
-- by platform_rw's default privileges). On the droplet dbt runs AS platform_rw, so
-- the bootstrap default privileges already grant app_read and platform_rw is not
-- the owner of core.entity_access (created by the superuser) - GRANT ... ON ALL
-- TABLES would then error on it. Wrap so the redundant grants are skipped there.
DO $$
BEGIN
  GRANT USAGE ON SCHEMA core, serving TO app_read;
  GRANT SELECT ON ALL TABLES IN SCHEMA core, serving TO app_read;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'app_read grants skipped (running as non-owner); bootstrap default privileges apply';
END $$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.table_schema, c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.column_name = 'entity_id'
      AND c.table_schema IN ('core', 'serving')
      AND t.table_type = 'BASE TABLE'
      -- never enable RLS on the control table itself: its policy would query
      -- itself and recurse infinitely.
      AND NOT (c.table_schema = 'core' AND c.table_name = 'entity_access')
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', r.table_schema, r.table_name);
    EXECUTE format('DROP POLICY IF EXISTS rls_entity ON %I.%I;', r.table_schema, r.table_name);
    EXECUTE format(
      'CREATE POLICY rls_entity ON %I.%I FOR SELECT USING (core.current_role_can_see(entity_id));',
      r.table_schema, r.table_name
    );
  END LOOP;
END $$;

-- core and serving models are materialized as TABLES with an entity_id column,
-- so the loop above secures each one directly. If a serving model is ever built
-- as a VIEW instead, make it security_invoker so RLS on its core base applies.
