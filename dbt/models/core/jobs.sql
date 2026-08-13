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
aj  as (select * from job where source = 'report_all_jobs'),

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
            ("swp.job_number", "swp.observed_at"),
            ("aj.job_number",  "aj.observed_at")
        ]) }}                                       as job_number,
        {{ pick_latest([
            ("enr.service_date", "enr.observed_at"),
            ("swp.service_date", "swp.observed_at"),
            ("aj.service_date",  "aj.observed_at")
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
            coalesce(swp.observed_at, '-infinity'::timestamptz),
            coalesce(aj.observed_at,  '-infinity'::timestamptz)
        )                                           as job_synced_at
    from base b
    left join enr on enr.job_key = b.job_key
    left join swp on swp.job_key = b.job_key
    left join aj  on aj.job_key  = b.job_key
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
    -- Prefer the JOB's own branch over the opportunity's. All Jobs reports it on
    -- 100% of its rows; the opportunity carries it on far fewer, and the branch is
    -- a property of where the job was booked. This is what feeds
    -- core.lines_of_business, so a null here silently becomes a `local` fallback.
    coalesce(aj.branch_name, o.branch_name) as branch_name,
    o.estimated_final_total,
    coalesce(o.is_deleted, false)       as is_deleted,

    -- Everything below comes from the All Jobs report and from nowhere else. It is
    -- joined directly rather than resolved through pick_latest because there is no
    -- second source to disagree with - see int_report_all_jobs_latest for the full
    -- reasoning. The API alternative is the Premium per-job endpoint, the most
    -- expensive call SmartMoving sells; this costs zero quota.
    aj.origin_street, aj.origin_city, aj.origin_state, aj.origin_zip,
    aj.origin_unit, aj.origin_type, aj.origin_address_full,
    aj.destination_street, aj.destination_city, aj.destination_state,
    aj.destination_zip, aj.destination_unit, aj.destination_type,
    aj.destination_address_full,

    aj.job_type_name,
    aj.opportunity_type_name,
    aj.pricing_method,
    aj.crew_member_names,
    aj.truck_names,
    aj.job_rating,
    aj.move_date_is_tbd,

    aj.created_date_local               as job_created_date_local,
    aj.booked_date_local                as job_booked_date_local,
    aj.end_date_local,
    aj.start_at_utc,
    aj.end_at_utc,
    aj.completed_date_local,
    aj.closed_date_local,

    aj.total_estimated_cost,
    aj.total_actual_cost,
    aj.actual_labor_cost, aj.actual_materials_cost, aj.actual_fuel_cost,
    aj.actual_insurance_cost, aj.actual_valuation_cost,
    aj.actual_additional_services_cost, aj.actual_other_fees_cost,
    aj.actual_trip_fees_cost, aj.actual_storage_in_transit_cost,
    aj.actual_prepaid_storage_cost, aj.actual_warehouse_handling_cost,
    aj.actual_truck_fees_cost, aj.actual_travel_time_fees_cost,
    aj.actual_credit_card_fees_cost, aj.actual_tax_amount, aj.actual_discount,
    aj.tip_amount, aj.wages,

    aj.est_crew_count, aj.actual_crew_count,
    aj.est_truck_count, aj.actual_truck_count,
    aj.est_time_hours, aj.actual_time_hours, aj.time_deductions_minutes,
    aj.origin_to_destination_mileage, aj.round_trip_mileage,
    aj.hourly_rate_quoted, aj.hourly_rate_billed,
    aj.volume_cuft, aj.weight_lbs,

    coalesce(o.timezone, i.timezone)    as timezone,
    greatest(r.job_synced_at, coalesce(o.synced_at, '-infinity'::timestamptz)) as synced_at
from resolved r
left join opportunities o
       on o.source_instance_id = r.source_instance_id
      and o.external_opportunity_id = r.external_opportunity_id
left join {{ ref('int_report_all_jobs_latest') }} aj
       on aj.job_key = r.job_key
left join service_types st
       on st.source_instance_id = r.source_instance_id
      and st.service_type_id = r.service_type_id
left join {{ ref('dim_instance') }} i
       on i.instance_id = r.source_instance_id
