-- serving.jobs_upcoming_v1 - PUBLIC CONTRACT (Operations).
-- Upcoming jobs for the next 10 days, one row per job. Consumed by app teams
-- via the app_read role (RLS-scoped by entity_id). Additive changes ship freely;
-- breaking changes require a v2 with 90-day overlap.
--
-- "Today" is evaluated in the entity's operating timezone (all EcoMovers
-- branches are America/Los_Angeles). When an entity in another timezone is
-- onboarded, this generalizes to a per-branch/per-entity timezone join.

{% set today_local = "(now() at time zone 'America/Los_Angeles')::date" %}

select
    job_key,
    entity_id,
    source_instance_id,
    external_job_id,
    job_number,
    quote_number,
    opportunity_status_label            as status,
    service_date,
    (service_date - {{ today_local }})  as days_until_service,
    service_type_name,
    customer_name,
    customer_phone,
    customer_email,
    customer_address,
    synced_at
from {{ ref('jobs') }}
where service_date >= {{ today_local }}
  and service_date <  {{ today_local }} + 11
