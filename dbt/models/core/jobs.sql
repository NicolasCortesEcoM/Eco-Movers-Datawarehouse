-- core.jobs - canonical jobs. Grain: one row per (source_instance_id, external_job_id).
--
-- Job facts resolve through the observation layer (int_job_latest_by_source);
-- opportunity and customer facts come from core.opportunities, which resolved them
-- the same way. Nothing here re-derives a fact another model already owns.
--
-- CONTRACT NOTE: serving.jobs_upcoming_v1 reads job_key, job_number, quote_number,
-- opportunity_status_label, service_date, service_type_name, customer_*, timezone
-- and synced_at from this model. Those column names are load-bearing - add freely,
-- rename nothing without a serving v2.
--
-- Once report_all_jobs lands (Phase 5) it becomes another arm of
-- int_job_observations and brings structured origin/destination, actual costs and
-- lifecycle timestamps. This model gains columns; it does not get restructured.

with job as (
    select * from {{ ref('int_job_latest_by_source') }}
),

enr as (select * from job where source = 'api_enrichment'),
swp as (select * from job where source = 'api_sweep'),

base as (
    select distinct job_key, entity_id, source_instance_id, external_job_id
    from job
),

opportunities as (
    select * from {{ ref('opportunities') }}
),

service_types as (
    select * from {{ ref('stg_smartmoving__service_types') }}
),

resolved as (
    select
        b.job_key,
        b.entity_id,
        b.source_instance_id,
        b.external_job_id,

        {{ pick_latest([
            ("enr.external_opportunity_id", "enr.observed_at"),
            ("swp.external_opportunity_id", "swp.observed_at")
        ]) }}                                       as external_opportunity_id,
        {{ pick_latest([
            ("enr.job_number", "enr.observed_at"),
            ("swp.job_number", "swp.observed_at")
        ]) }}                                       as job_number,
        {{ pick_latest([
            ("enr.service_date", "enr.observed_at"),
            ("swp.service_date", "swp.observed_at")
        ]) }}                                       as service_date,
        {{ pick_latest([
            ("enr.service_type_id", "enr.observed_at"),
            ("swp.service_type_id", "swp.observed_at")
        ]) }}                                       as service_type_id,

        -- enrichment-only depth
        {{ pick_latest([("enr.is_confirmed", "enr.observed_at")]) }}    as is_confirmed,
        {{ pick_latest([("enr.total_tips", "enr.observed_at")]) }}      as total_tips,
        {{ pick_latest([("enr.arrival_window_description", "enr.observed_at")]) }}
                                                                        as arrival_window_description,
        {{ pick_latest([("enr.labor_time_estimated", "enr.observed_at")]) }}  as labor_time_estimated,
        {{ pick_latest([("enr.labor_time_actual", "enr.observed_at")]) }}     as labor_time_actual,
        {{ pick_latest([("enr.travel_time_estimated", "enr.observed_at")]) }} as travel_time_estimated,
        {{ pick_latest([("enr.travel_time_actual", "enr.observed_at")]) }}    as travel_time_actual,
        {{ pick_latest([("enr.billable_hours", "enr.observed_at")]) }}        as billable_hours,

        greatest(
            coalesce(enr.observed_at, '-infinity'::timestamptz),
            coalesce(swp.observed_at, '-infinity'::timestamptz)
        )                                           as job_synced_at
    from base b
    left join enr on enr.job_key = b.job_key
    left join swp on swp.job_key = b.job_key
)

select
    r.job_key,
    r.entity_id,
    r.source_instance_id,
    r.external_job_id,
    r.job_number,
    r.external_opportunity_id,

    o.quote_number,
    o.status_code                       as opportunity_status_code,
    o.status_label                      as opportunity_status_label,
    o.status_category                   as opportunity_status_category,
    coalesce(o.is_booked,    false)     as is_booked,
    coalesce(o.is_completed, false)     as is_completed,
    coalesce(o.is_cancelled, false)     as is_cancelled,
    coalesce(o.is_lost,      false)     as is_lost,
    coalesce(o.is_bad_lead,  false)     as is_bad_lead,
    coalesce(o.is_open,      false)     as is_open,
    o.pipeline_status,

    r.service_date,
    r.service_type_id,
    st.service_type_name,
    r.is_confirmed,
    r.total_tips,
    r.arrival_window_description,
    r.labor_time_estimated,
    r.labor_time_actual,
    r.travel_time_estimated,
    r.travel_time_actual,
    r.billable_hours,

    o.external_customer_id,
    o.customer_name,
    o.customer_phone,
    o.customer_email,
    o.customer_address,
    o.branch_name,
    o.estimated_final_total,
    coalesce(o.is_deleted, false)       as is_deleted,

    coalesce(o.timezone, i.timezone)    as timezone,
    greatest(r.job_synced_at, coalesce(o.synced_at, '-infinity'::timestamptz)) as synced_at
from resolved r
left join opportunities o
       on o.source_instance_id = r.source_instance_id
      and o.external_opportunity_id = r.external_opportunity_id
left join service_types st
       on st.source_instance_id = r.source_instance_id
      and st.service_type_id = r.service_type_id
left join {{ ref('dim_instance') }} i
       on i.instance_id = r.source_instance_id
