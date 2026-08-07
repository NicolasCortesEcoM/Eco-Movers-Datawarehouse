{#
  Re-apply grants + Row-Level Security after a dbt build.

  Wired as an on-run-end hook in dbt_project.yml. dbt drops and recreates core and
  serving tables, and a dropped table takes its policies with it - so between the
  build and a manual `psql -f sql/10_apply_rls.sql` there is a window in which
  app_read can read EVERY entity's rows. At 5 builds a day that window is not
  theoretical, and "remember to run the script" is not a control.

  sql/10_apply_rls.sql stays as the manual escape hatch and as the readable
  reference; this macro is a direct port of it. Keep the two in step.

  on-run-end runs once per invocation, after all models. It is skipped when the
  run selected no models, which is correct: nothing was dropped.
#}
{% macro apply_rls() %}
  {% if execute %}

    {% set grant_sql %}
      DO $$
      BEGIN
        GRANT USAGE ON SCHEMA core, serving TO app_read;
        GRANT SELECT ON ALL TABLES IN SCHEMA core, serving TO app_read;
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'app_read grants skipped (running as non-owner); bootstrap default privileges apply';
      WHEN undefined_object THEN
        RAISE NOTICE 'app_read role not present; skipping grants';
      END $$;
    {% endset %}

    {% set policy_sql %}
      DO $$
      DECLARE r record;
      BEGIN
        FOR r IN
          SELECT c.table_schema, c.table_name
          FROM information_schema.columns c
          JOIN information_schema.tables t
            ON t.table_schema = c.table_schema AND t.table_name = c.table_name
          WHERE c.column_name = 'entity_id'
            AND c.table_schema IN ('core', 'serving')
            AND t.table_type = 'BASE TABLE'
            -- never enable RLS on the control table itself: its policy would
            -- query itself and recurse infinitely.
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
    {% endset %}

    {% do run_query(grant_sql) %}
    {% do run_query(policy_sql) %}
    {% do log("apply_rls: grants + RLS policies re-applied on core + serving", info=True) %}

  {% endif %}
{% endmacro %}
