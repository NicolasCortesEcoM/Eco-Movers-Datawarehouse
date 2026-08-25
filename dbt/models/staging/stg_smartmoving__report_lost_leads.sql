-- The Lost Leads & Opportunities Details scheduled report, typed.
--
-- WHY THIS REPORT EXISTS SEPARATELY FROM Lead Status. Lead Status says an
-- opportunity was lost. This one says WHEN it was lost and WHY - `Lost Date` and
-- `Reason` ("Lost price too high", "Went with another company") appear in no other
-- free source, and the API only gives them one opportunity at a time.
--
-- It also carries `Time to First Contact`, which is the single number a sales team
-- can act on: the gap between a lead arriving and someone answering it. Lead Status
-- has `Time to Contact` for everyone; having it for the lost ones specifically is
-- what makes the comparison mean anything.
--
-- WHAT IT CANNOT DO: it is one slice of the universe - lost records only. It is
-- never a denominator. Conversion rates are counted on Lead Status; this report
-- explains the numerator's failures, it does not size them.
--
-- All generations are kept (this is a view); collapsing to the newest observation
-- per row_key is the observation layer's job, not staging's.
--
-- API quota cost: ZERO.

with report as (
    select * from {{ source('smartmoving', 'report_lost_leads') }}
),

instances as (
    -- crm_timezone, not `timezone`: the report renders in whatever zone the CRM is
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

        nullif(trim(r.row_data ->> 'Quote #'), '')      as quote_number,
        nullif(trim(r.row_data ->> 'Name'), '')         as customer_name,
        nullif(trim(r.row_data ->> 'Reason'), '')       as lost_reason,

        -- All three are local business dates, never timezone-converted: the vendor
        -- renders them as bare M/D/YYYY with no offset, and rpt_date also absorbs
        -- the '0/0/0' it writes instead of leaving a cell blank.
        {{ rpt_date("r.row_data ->> 'Date Received'") }} as received_date_local,
        {{ rpt_date("r.row_data ->> 'Lost Date'") }}     as lost_date_local,
        {{ rpt_date("r.row_data ->> 'Move Date'") }}     as service_date_local,

        {{ rpt_minutes("r.row_data ->> 'Time to First Contact'") }} as time_to_first_contact_minutes,
        {{ rpt_num("r.row_data ->> 'Est. Dollar Amount'") }}        as estimated_amount,

        i.crm_timezone,
        r.row_data
    from report r
    left join instances i on i.instance_id = r.source_instance_id
)

select
    source_instance_id || ':' || row_key || ':'
        || to_char(report_generated_at, 'YYYYMMDDHH24MISS')  as report_row_key,
    source_instance_id,
    entity_id,
    report_generated_at,
    row_key,
    quote_number,
    customer_name,
    lost_reason,
    received_date_local,
    lost_date_local,
    service_date_local,
    time_to_first_contact_minutes,
    estimated_amount,
    crm_timezone,
    _ingested_at,
    _source_email,
    -- the verbatim export row, so a vendor column we do not yet promote is never lost
    row_data
from typed
