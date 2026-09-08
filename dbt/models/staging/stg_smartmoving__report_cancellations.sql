-- The Cancellation Details scheduled report, typed.
--
-- WHY IT MATTERS: `Cancelled Date` exists in NO other source. Lead Status reports that
-- an opportunity is cancelled and the platform integer confirms the outcome, but
-- neither says WHEN - and "cancelled" without a date cannot be counted per month, put
-- on a trend, or compared against the booking that preceded it. `Amount` is the
-- revenue that walked, and `Reason` is why.
--
-- It was landing and row-count verified by n8n since 2026-08, and nothing read it -
-- the table was not even declared as a dbt source. This model is the first half of
-- closing that; core promotion is the second.
--
-- WHAT IT CANNOT DO: cancellations only. Like Lost Leads it is one slice of the
-- universe and is never a denominator. It explains an outcome; it does not size one.
--
-- All generations kept (a view). Collapsing to the newest observation per row_key is
-- the observation layer's job, not staging's.
--
-- API quota cost: ZERO.

with report as (
    select * from {{ source('smartmoving', 'report_cancellations') }}
),

instances as (
    -- crm_timezone, not `timezone`: the report renders in the zone the CRM is
    -- configured with, which is not necessarily where the branch operates.
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

        nullif(trim(r.row_data ->> 'Quote #'), '')        as quote_number,
        nullif(trim(r.row_data ->> 'Name'), '')           as customer_name,
        nullif(trim(r.row_data ->> 'Email'), '')          as customer_email,
        nullif(trim(r.row_data ->> 'Phone'), '')          as customer_phone,
        nullif(trim(r.row_data ->> 'Reason'), '')         as cancellation_reason,
        nullif(trim(r.row_data ->> 'Service Type'), '')   as service_type_name,

        -- Local business dates, never timezone-converted: the vendor renders bare
        -- M/D/YYYY with no offset, and rpt_date also absorbs the '0/0/0' it writes
        -- instead of leaving a cell blank.
        {{ rpt_date("r.row_data ->> 'Cancelled Date'") }} as cancelled_date_local,
        {{ rpt_date("r.row_data ->> 'Move Date'") }}      as service_date_local,

        -- The revenue that walked. Cast to numeric at this boundary like all money.
        {{ rpt_num("r.row_data ->> 'Amount'") }}          as cancelled_amount,

        i.crm_timezone,
        r.row_data
    from report r
    left join instances i on i.instance_id = r.source_instance_id
)

select
    source_instance_id || ':' || row_key || ':'
        || to_char(report_generated_at, 'YYYYMMDDHH24MISS') as report_row_key,
    source_instance_id,
    entity_id,
    report_generated_at,
    row_key,
    quote_number,
    customer_name,
    customer_email,
    customer_phone,
    cancellation_reason,
    service_type_name,
    cancelled_date_local,
    service_date_local,
    cancelled_amount,
    crm_timezone,
    _ingested_at,
    _source_email,
    -- the verbatim export row, so a vendor column not yet promoted is never lost
    row_data
from typed
