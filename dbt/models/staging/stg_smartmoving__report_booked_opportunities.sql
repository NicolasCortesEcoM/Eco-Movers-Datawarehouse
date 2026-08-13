-- The Booked Opportunities by Date Booked report, typed. OPPORTUNITY grain.
--
-- DELIBERATELY THIN. Of its 20 columns, all but three are already covered better
-- elsewhere, and promoting them again would mean more `pick_latest` branches to
-- maintain for no new information:
--
--   Customer name/email/phone, addresses, hourly rate, booked date, service date,
--   volume, weight       -> report_all_jobs carries all of these, structured
--   Estimated Amount, branch, estimator, coordinator, sales person, referral,
--   service type, status  -> report_lead_status already carries these
--
-- What is genuinely unique:
--
--   * `Invoiced Amount` - what the customer was actually BILLED. No other source
--     has it. All Jobs carries `Total Actual Cost`, which is cost, not revenue;
--     Lead Status carries `Estimated Revenue`, which is a quote. This is the only
--     column in the warehouse that states realised revenue.
--   * `Booked Date` at opportunity grain, for opportunities with no job row yet.
--   * The customer contact, for the same reason.
--
-- Everything else stays in row_data, available if it is ever needed, promoted to a
-- column only when something actually reads it.

with report as (
    select * from {{ source('smartmoving', 'report_booked_opportunities') }}
),

instances as (
    select instance_id, crm_timezone from {{ ref('dim_instance') }}
)

select
    r.source_instance_id || ':' || r.row_key || ':'
        || to_char(r.report_generated_at, 'YYYYMMDDHH24MISS') as report_row_key,
    r.source_instance_id,
    r.entity_id,
    r.report_generated_at,
    r.row_key,

    nullif(trim(r.row_data ->> 'Quote #'), '')          as quote_number,
    nullif(trim(r.row_data ->> 'Status'), '')           as status_raw,
    nullif(trim(r.row_data ->> 'Customer Name'), '')    as customer_name,
    nullif(trim(r.row_data ->> 'Email'), '')            as customer_email,
    nullif(trim(r.row_data ->> 'Phone Number'), '')     as customer_phone,

    -- The point of this model.
    {{ rpt_num("r.row_data ->> 'Invoiced Amount'") }}   as invoiced_amount,
    {{ rpt_num("r.row_data ->> 'Estimated Amount'") }}  as estimated_amount,

    -- A local business date, never timezone-converted.
    {{ rpt_date("r.row_data ->> 'Booked Date'") }}      as booked_date_local,
    {{ rpt_date("r.row_data ->> 'Service Date'") }}     as service_date_local,

    i.crm_timezone,
    r._ingested_at,
    r._source_email,
    r.row_data
from report r
left join instances i on i.instance_id = r.source_instance_id
