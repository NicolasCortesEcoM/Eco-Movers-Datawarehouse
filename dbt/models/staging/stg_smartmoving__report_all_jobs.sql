-- The All Jobs scheduled report, typed. 89 columns, JOB grain.
--
-- THE RICHEST SOURCE IN THE WAREHOUSE, and the only one that carries all of:
--   * the job GUID, so a report row attaches to a job with no crosswalk at all
--   * structured origin/destination (street, city, state, zip, unit, type)
--   * the full ACTUAL cost breakdown - labor, materials, fuel, valuation, storage,
--     trip fees, truck fees, travel time, tax, discount, tips
--   * lifecycle timestamps: created, booked, completed, closed, start, end
--   * crew names, truck names, mileage, pricing method, job rating
--
-- None of that is reachable from the API without the Premium per-job endpoint, which
-- is the most expensive call SmartMoving offers. This report costs zero quota.
--
-- `Job Number` is `<quote>-<seq>` ("11209-1"), which gives a SECOND, independent path
-- to the opportunity - useful as a cross-check against the GUID, not as the primary.
--
-- Time handling, and the `at Utc` suffix means THREE different things in this one
-- report. All measured, none assumed:
--   * `Start/End Time Utc` carry an EXPLICIT offset ("8:45:00 AM -07:00") - already
--     unambiguous instants, so crm_timezone must NOT be applied.
--   * `Completed/Closed at Utc` are BARE DATES ("6/20/2026"), not timestamps at all.
--   * `Created/Booked at Utc` and `Job Date` are local business dates.
-- Getting this wrong is silent: the first version treated Start/Completed as
-- crm_timezone wall clocks and parsed 0 of 6,897 rows without any error.
--
-- All generations are kept; collapsing to the newest is the job of
-- int_report_all_jobs_latest, not of staging.

with report as (
    select * from {{ source('smartmoving', 'report_all_jobs') }}
),

instances as (
    select instance_id, crm_timezone from {{ ref('dim_instance') }}
),

typed as (
    select
        r.source_instance_id,
        r.entity_id,
        r.report_generated_at,
        r.row_key,
        r._ingested_at,
        r._source_email,
        i.crm_timezone,

        -- Identity. row_key is the Job Id GUID for this report.
        nullif(trim(r.row_data ->> 'Job Id'), '')       as external_job_id,
        nullif(trim(r.row_data ->> 'Job Number'), '')   as job_number,
        -- `<quote>-<seq>`: the quote number is everything before the first dash.
        nullif(split_part(trim(r.row_data ->> 'Job Number'), '-', 1), '') as quote_number,

        nullif(trim(r.row_data ->> 'Opportunity Status'), '') as opportunity_status_raw,
        nullif(trim(r.row_data ->> 'Opportunity Type'), '')   as opportunity_type_name,
        nullif(trim(r.row_data ->> 'Job Type'), '')           as job_type_name,
        nullif(trim(r.row_data ->> 'Branch Name'), '')        as branch_name,

        -- People
        nullif(trim(r.row_data ->> 'Customer Name'), '')      as customer_name,
        nullif(trim(r.row_data ->> 'Customer Email'), '')     as customer_email,
        nullif(trim(r.row_data ->> 'Customer Phone'), '')     as customer_phone,
        nullif(trim(r.row_data ->> 'Sales Person Name'), '')  as sales_person,
        nullif(trim(r.row_data ->> 'Estimator Name'), '')     as estimator_name,
        nullif(trim(r.row_data ->> 'Move Coordinator Name'), '') as move_coordinator_name,
        nullif(trim(r.row_data ->> 'Referral Source'), '')    as referral_source,
        nullif(trim(r.row_data ->> 'Affiliate Name'), '')     as affiliate_name,
        nullif(trim(r.row_data ->> 'Crew Member Names'), '')  as crew_member_names,
        nullif(trim(r.row_data ->> 'Truck Names'), '')        as truck_names,

        -- Structured addresses. THE reason this report matters for jobs: the API
        -- returns only flat address strings.
        nullif(trim(r.row_data ->> 'Origin Street'), '')      as origin_street,
        nullif(trim(r.row_data ->> 'Origin City'), '')        as origin_city,
        nullif(trim(r.row_data ->> 'Origin State'), '')       as origin_state,
        nullif(trim(r.row_data ->> 'Origin Zip'), '')         as origin_zip,
        nullif(trim(r.row_data ->> 'Origin Unit'), '')        as origin_unit,
        nullif(trim(r.row_data ->> 'Origin Type'), '')        as origin_type,
        nullif(trim(r.row_data ->> 'Origin Address'), '')     as origin_address_full,
        nullif(trim(r.row_data ->> 'Destination Street'), '') as destination_street,
        nullif(trim(r.row_data ->> 'Destination City'), '')   as destination_city,
        nullif(trim(r.row_data ->> 'Destination State'), '')  as destination_state,
        nullif(trim(r.row_data ->> 'Destination Zip'), '')    as destination_zip,
        nullif(trim(r.row_data ->> 'Destination Unit'), '')   as destination_unit,
        nullif(trim(r.row_data ->> 'Destination Type'), '')   as destination_type,
        nullif(trim(r.row_data ->> 'Destination Address'), '') as destination_address_full,

        -- Local business dates: never timezone-converted.
        {{ rpt_date("r.row_data ->> 'Job Date'") }}           as service_date_local,
        {{ rpt_date("r.row_data ->> 'End Date'") }}           as end_date_local,
        {{ rpt_date("r.row_data ->> 'Created at Utc'") }}     as created_date_local,
        {{ rpt_date("r.row_data ->> 'Booked at Utc'") }}      as booked_date_local,

        -- MEASURED, not assumed - and it contradicts what the column names suggest.
        -- Start/End carry an EXPLICIT offset ("6/20/2026 8:45:00 AM -07:00"), so they
        -- are already unambiguous instants: applying crm_timezone would shift them
        -- twice. All 2,821 non-empty values match that shape.
        {{ rpt_ts_offset("r.row_data ->> 'Start Time Utc'") }}  as start_at_utc,
        {{ rpt_ts_offset("r.row_data ->> 'End Time Utc'") }}    as end_at_utc,

        -- Completed/Closed are BARE DATES ("6/20/2026") despite the `at Utc` suffix -
        -- all 2,874 non-empty values. Treating them as timestamps parsed nothing at
        -- all: the first build produced 0 of 6,897. They are local business dates and
        -- are named accordingly.
        {{ rpt_date("r.row_data ->> 'Completed at Utc'") }}     as completed_date_local,
        {{ rpt_date("r.row_data ->> 'Closed at Utc'") }}        as closed_date_local,

        {{ rpt_bool("r.row_data ->> 'Move Date Is TBD'") }}   as move_date_is_tbd,

        -- Estimated cost breakdown
        {{ rpt_num("r.row_data ->> 'Estimated Labor Cost'") }}               as est_labor_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Materials Cost'") }}           as est_materials_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Fuel Surcharges Cost'") }}     as est_fuel_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Insurance Cost'") }}           as est_insurance_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Valuation Cost'") }}           as est_valuation_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Additional Services Cost'") }} as est_additional_services_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Other Fees Cost'") }}          as est_other_fees_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Trip Fees Cost'") }}           as est_trip_fees_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Storage in Transit Cost'") }}  as est_storage_in_transit_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Prepaid Storage Cost'") }}     as est_prepaid_storage_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Warehouse Handling Cost'") }}  as est_warehouse_handling_cost,
        {{ rpt_num("r.row_data ->> 'Truck Fees Estimated Cost'") }}          as est_truck_fees_cost,
        {{ rpt_num("r.row_data ->> 'Travel Time Fees Estimated Cost'") }}    as est_travel_time_fees_cost,
        {{ rpt_num("r.row_data ->> 'Estimated Tax Amount'") }}               as est_tax_amount,
        {{ rpt_num("r.row_data ->> 'Estimated Discount'") }}                 as est_discount,
        {{ rpt_num("r.row_data ->> 'Total Estimated Cost'") }}               as total_estimated_cost,

        -- Actual cost breakdown. Nothing else in the warehouse carries these.
        {{ rpt_num("r.row_data ->> 'Actual Labor Cost'") }}                  as actual_labor_cost,
        {{ rpt_num("r.row_data ->> 'Actual Materials Cost'") }}              as actual_materials_cost,
        {{ rpt_num("r.row_data ->> 'Actual Fuel Surcharges Cost'") }}        as actual_fuel_cost,
        {{ rpt_num("r.row_data ->> 'Actual Insurance Cost'") }}              as actual_insurance_cost,
        {{ rpt_num("r.row_data ->> 'Actual Valuation Cost'") }}              as actual_valuation_cost,
        {{ rpt_num("r.row_data ->> 'Actual Additional Services Cost'") }}    as actual_additional_services_cost,
        {{ rpt_num("r.row_data ->> 'Actual Other Fees Cost'") }}             as actual_other_fees_cost,
        {{ rpt_num("r.row_data ->> 'Actual Trip Fees Cost'") }}              as actual_trip_fees_cost,
        {{ rpt_num("r.row_data ->> 'Actual Storage in Transit Cost'") }}     as actual_storage_in_transit_cost,
        {{ rpt_num("r.row_data ->> 'Actual Prepaid Storage Cost'") }}        as actual_prepaid_storage_cost,
        {{ rpt_num("r.row_data ->> 'Actual Warehouse Handling Cost'") }}     as actual_warehouse_handling_cost,
        {{ rpt_num("r.row_data ->> 'Truck Fees Actual Cost'") }}             as actual_truck_fees_cost,
        {{ rpt_num("r.row_data ->> 'Travel Time Fees Actual Cost'") }}       as actual_travel_time_fees_cost,
        {{ rpt_num("r.row_data ->> 'Credit Card Fees Actual Cost'") }}       as actual_credit_card_fees_cost,
        {{ rpt_num("r.row_data ->> 'Actual Tax Amount'") }}                  as actual_tax_amount,
        {{ rpt_num("r.row_data ->> 'Actual Discount'") }}                    as actual_discount,
        {{ rpt_num("r.row_data ->> 'Total Actual Cost'") }}                  as total_actual_cost,
        {{ rpt_num("r.row_data ->> 'Tip Amount'") }}                         as tip_amount,
        {{ rpt_num("r.row_data ->> 'Wages'") }}                              as wages,

        -- Operations
        {{ rpt_num("r.row_data ->> 'Estimated Number of Crew'") }}   as est_crew_count,
        {{ rpt_num("r.row_data ->> 'Actual Number of Crew'") }}      as actual_crew_count,
        {{ rpt_num("r.row_data ->> 'Estimated Number of Trucks'") }} as est_truck_count,
        {{ rpt_num("r.row_data ->> 'Actual Number of Trucks'") }}    as actual_truck_count,
        {{ rpt_num("r.row_data ->> 'Total Estimated Time Hours'") }} as est_time_hours,
        {{ rpt_num("r.row_data ->> 'Actual Time Hours'") }}          as actual_time_hours,
        {{ rpt_num("r.row_data ->> 'Total Job Time Deductions Minutes'") }} as time_deductions_minutes,
        {{ rpt_num("r.row_data ->> 'Origin to Destination Mileage'") }} as origin_to_destination_mileage,
        {{ rpt_num("r.row_data ->> 'Round Trip Mileage'") }}         as round_trip_mileage,
        {{ rpt_num("r.row_data ->> 'Hourly Rate Quoted'") }}         as hourly_rate_quoted,
        {{ rpt_num("r.row_data ->> 'Hourly Rate Billed'") }}         as hourly_rate_billed,
        {{ rpt_num("r.row_data ->> 'Job Rating'") }}                 as job_rating,
        nullif(trim(r.row_data ->> 'Pricing Method'), '')            as pricing_method,

        {{ rpt_cuft("r.row_data ->> 'Volume'") }}                    as volume_cuft,
        {{ rpt_lbs("r.row_data ->> 'Weight'") }}                     as weight_lbs,

        r.row_data
    from report r
    left join instances i on i.instance_id = r.source_instance_id
)

select
    source_instance_id || ':' || external_job_id as job_key,
    source_instance_id || ':' || row_key || ':'
        || to_char(report_generated_at, 'YYYYMMDDHH24MISS') as report_row_key,
    *
from typed
