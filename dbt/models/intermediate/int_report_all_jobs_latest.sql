-- Newest All Jobs report row per job.
--
-- WHY THIS IS NOT AN OBSERVATION ARM, and the reasoning generalises:
--
-- The observation layer exists to resolve DISAGREEMENT. When several sources report
-- the same field, pick_latest decides per field which one wins. That machinery earns
-- its complexity only where sources actually overlap.
--
-- For the ~60 fields this report contributes - structured addresses, the actual cost
-- breakdown, lifecycle timestamps, crew, mileage - **All Jobs is the only source in
-- the warehouse**. There is nothing to reconcile. Routing them through
-- int_job_observations would mean adding ~60 nullable columns to every other arm, so
-- that each one can contribute NULL to all of them, in order to resolve a conflict
-- that cannot occur.
--
-- So the split is by whether a conflict is possible, not by which table a field
-- came from:
--   * job_number and service_date OVERLAP with the API  -> observation arm
--   * everything else is All Jobs alone                 -> this model, joined directly
--
-- Collapsing to the newest generation is the whole job here. `distinct on` is right
-- rather than pick_latest for the same reason: one source means one winner per row,
-- not per field.

{{ config(materialized='view') }}

select distinct on (job_key)
    job_key,
    source_instance_id,
    entity_id,
    external_job_id,
    quote_number,
    report_generated_at             as observed_at,

    -- The two fields that OVERLAP with the API sources. They are also read from
    -- here by the report_all_jobs arm of int_job_observations, which is where the
    -- freshness race against the API is decided.
    job_number,
    service_date_local,

    opportunity_status_raw,
    opportunity_type_name,
    job_type_name,
    branch_name,

    customer_name,
    customer_email,
    customer_phone,
    sales_person,
    estimator_name,
    move_coordinator_name,
    referral_source,
    affiliate_name,
    crew_member_names,
    truck_names,

    origin_street, origin_city, origin_state, origin_zip, origin_unit, origin_type,
    origin_address_full,
    destination_street, destination_city, destination_state, destination_zip,
    destination_unit, destination_type, destination_address_full,

    end_date_local,
    created_date_local,
    booked_date_local,
    start_at_utc,
    end_at_utc,
    completed_date_local,
    closed_date_local,
    move_date_is_tbd,

    est_labor_cost, est_materials_cost, est_fuel_cost, est_insurance_cost,
    est_valuation_cost, est_additional_services_cost, est_other_fees_cost,
    est_trip_fees_cost, est_storage_in_transit_cost, est_prepaid_storage_cost,
    est_warehouse_handling_cost, est_truck_fees_cost, est_travel_time_fees_cost,
    est_tax_amount, est_discount, total_estimated_cost,

    actual_labor_cost, actual_materials_cost, actual_fuel_cost, actual_insurance_cost,
    actual_valuation_cost, actual_additional_services_cost, actual_other_fees_cost,
    actual_trip_fees_cost, actual_storage_in_transit_cost, actual_prepaid_storage_cost,
    actual_warehouse_handling_cost, actual_truck_fees_cost, actual_travel_time_fees_cost,
    actual_credit_card_fees_cost, actual_tax_amount, actual_discount,
    total_actual_cost, tip_amount, wages,

    est_crew_count, actual_crew_count, est_truck_count, actual_truck_count,
    est_time_hours, actual_time_hours, time_deductions_minutes,
    origin_to_destination_mileage, round_trip_mileage,
    hourly_rate_quoted, hourly_rate_billed, job_rating, pricing_method,
    volume_cuft, weight_lbs
from {{ ref('stg_smartmoving__report_all_jobs') }}
where external_job_id is not null
order by job_key, report_generated_at desc
