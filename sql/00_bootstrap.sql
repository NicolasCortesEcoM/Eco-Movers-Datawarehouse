-- 00_bootstrap.sql - schemas, roles, grants for the central Postgres store.
-- Idempotent: safe to run more than once. Run as a superuser / the DB admin.
--
-- Layers (CLAUDE.md): raw_smartmoving/staging/core -> dbt-only; marts -> BI;
-- serving -> the public contract other teams read.
-- Access model (decisions/0003): app_read may SELECT serving AND core (core is
-- "unstable, may change"); never raw_* or staging; never a vendor API key.

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw_smartmoving;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS serving;

-- ---------------------------------------------------------------------------
-- Roles
--   platform_rw : owned by the platform team; dlt + dbt connect as this.
--                 Owns every object, so it bypasses RLS by design.
--   app_read    : consumer apps connect as this (or a per-team role that
--                 inherits it). SELECT on serving + core only. RLS applies.
-- Passwords are NOT set here - set them out-of-band from .env, e.g.:
--   ALTER ROLE platform_rw LOGIN PASSWORD :'pw';   (psql -v pw=...)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_rw') THEN
    CREATE ROLE platform_rw LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_read') THEN
    CREATE ROLE app_read LOGIN;
  END IF;
END $$;

-- platform_rw owns and can do anything within these schemas.
GRANT ALL ON SCHEMA raw_smartmoving, staging, core, marts, serving TO platform_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE platform_rw IN SCHEMA raw_smartmoving, staging, core, marts, serving
  GRANT ALL ON TABLES TO platform_rw;

-- Consumers: usage on serving + core only, and SELECT (incl. future tables).
REVOKE ALL ON SCHEMA raw_smartmoving, staging, marts FROM app_read;
GRANT USAGE ON SCHEMA serving, core TO app_read;
GRANT SELECT ON ALL TABLES IN SCHEMA serving, core TO app_read;
ALTER DEFAULT PRIVILEGES FOR ROLE platform_rw IN SCHEMA serving, core
  GRANT SELECT ON TABLES TO app_read;

-- ---------------------------------------------------------------------------
-- Entity access map - the RLS key. A consumer sees an entity's rows only if
-- (role_name, entity_id) is listed here. current_user cannot be spoofed by a
-- non-superuser, so this is a real isolation boundary (unlike session GUCs).
-- Add a row per (consumer role, entity) they are allowed to read.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.entity_access (
  role_name  text NOT NULL,
  entity_id  text NOT NULL,
  PRIMARY KEY (role_name, entity_id)
);
GRANT SELECT ON core.entity_access TO app_read;

-- Phase 1: the one entity, readable by app_read.
INSERT INTO core.entity_access (role_name, entity_id)
VALUES ('app_read', 'ecomovers')
ON CONFLICT DO NOTHING;

-- Helper used by every RLS policy (see 10_apply_rls.sql).
CREATE OR REPLACE FUNCTION core.current_role_can_see(target_entity text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM core.entity_access
    WHERE role_name = current_user AND entity_id = target_entity
  );
$$;
