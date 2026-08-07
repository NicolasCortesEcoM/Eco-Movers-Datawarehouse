-- The Lead Status scheduled report, typed.
--
-- THE MOST IMPORTANT REPORT. Keyed on lead RECEIVED date, so one export returns
-- every lead and opportunity received in a period regardless of outcome - won,
-- lost, cancelled, bad, still open. Every other report is one slice of this; this
-- one is the denominator, and without it there is no conversion rate.
--
-- `status_raw` is the authoritative business outcome, carrying the lost/cancelled
-- subcategory ("Lost price too high"). It joins to dim_status_map, which covers
-- 99% of observed values. `lead_status_raw` is the CRM pipeline label - kept
-- because it is useful context, but it is NOT what metrics are counted on.
--
-- All generations are kept (this is a view): collapsing to the newest observation
-- per row_key is the observation layer's job, not staging's.
--
-- API quota cost: ZERO.

with report as (
    select * from {{ source('smartmoving', 'report_lead_status') }}
),

instances as (
    -- crm_timezone, not `timezone`: the report renders in whatever zone the CRM
    -- is configured with, which is not necessarily where the branch operates.
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

        nullif(trim(r.row_data ->> 'Quote #'), '')          as quote_number,
        nullif(trim(r.row_data ->> 'Status'), '')           as status_raw,
        nullif(trim(r.row_data ->> 'Lead Status'), '')      as lead_status_raw,
        nullif(trim(r.row_data ->> 'Branch Name'), '')      as branch_name,
        nullif(trim(r.row_data ->> 'Service Type'), '')     as service_type_name,
        nullif(trim(r.row_data ->> 'Sales Person'), '')     as sales_person,
        nullif(trim(r.row_data ->> 'Estimator'), '')        as estimator_name,
        nullif(trim(r.row_data ->> 'Move Coordinator'), '') as move_coordinator_name,
        nullif(trim(r.row_data ->> 'Referral Source'), '')  as referral_source,

        -- Received at / Quote Sent / Last Communication are wall-clock readings in
        -- crm_timezone; converted to true UTC instants here (CLAUDE.md rule 8).
        {{ rpt_ts("r.row_data ->> 'Received at'", 'i.crm_timezone') }}       as received_at_utc,
        {{ rpt_ts("r.row_data ->> 'Quote Sent'", 'i.crm_timezone') }}        as quote_sent_at_utc,
        {{ rpt_ts("r.row_data ->> 'Last Communication'", 'i.crm_timezone') }} as last_communication_at_utc,

        -- Service Date is a local business date; never timezone-converted.
        -- The vendor writes '0/0/0' rather than blank when there is no date.
        {{ rpt_date("r.row_data ->> 'Service Date'") }}     as service_date_local,

        {{ rpt_minutes("r.row_data ->> 'Time to Contact'") }} as time_to_contact_minutes,
        {{ rpt_num("r.row_data ->> 'Estimated Revenue'") }}   as estimated_revenue,
        {{ rpt_cuft("r.row_data ->> 'Volume/Weight'") }}      as volume_cuft,
        {{ rpt_lbs("r.row_data ->> 'Volume/Weight'") }}       as weight_lbs,

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
    status_raw,
    lead_status_raw,
    branch_name,
    service_type_name,
    sales_person,
    estimator_name,
    move_coordinator_name,
    referral_source,
    received_at_utc,
    quote_sent_at_utc,
    last_communication_at_utc,
    service_date_local,
    time_to_contact_minutes,
    estimated_revenue,
    volume_cuft,
    weight_lbs,
    crm_timezone,
    _ingested_at,
    _source_email,
    -- the verbatim export row, so a vendor column we do not yet promote is never lost
    row_data
from typed
