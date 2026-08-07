-- serving.jobs_upcoming_v1 - PUBLIC CONTRACT (Operations).
-- Upcoming jobs for the next 10 days, one row per job. Consumed by app teams
-- via the app_read role (RLS-scoped by entity_id). Additive changes ship freely;
-- breaking changes require a v2 with 90-day overlap.
--
-- "Today" is evaluated per row in that job's own timezone, carried through
-- core.jobs from core.branches / dim_instance. No zone is hardcoded, so a
-- company operating in another zone gets the right day without a model change.

select
    job_key,
    entity_id,
    source_instance_id,
    external_job_id,
    job_number,
    quote_number,
    opportunity_status_label                    as status,
    service_date,
    (service_date - {{ entity_today('timezone') }}) as days_until_service,
    service_type_name,
    customer_name,
    customer_phone,
    customer_email,
    customer_address,
    synced_at
from {{ ref('jobs') }}
where service_date >= {{ entity_today('timezone') }}
  and service_date <  {{ entity_today('timezone') }} + 11
