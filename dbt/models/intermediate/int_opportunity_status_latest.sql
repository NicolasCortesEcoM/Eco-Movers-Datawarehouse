-- Last-observation-wins status per opportunity, built purely from the webhook log
-- (Tier 0, zero API). Answers the #1 question - "how many opportunities do we
-- have right now, by status" - in real time, independent of any API call.
--
-- Grain: one row per (source_instance_id, external_opportunity_id). The hourly
-- /customers sweep (raw customers_service_window) remains the count-of-record;
-- this feed is the sub-minute, free approximation between sweeps. A nightly
-- reconciliation compares the two and alerts on divergence.

with events as (
    select * from {{ ref('stg_smartmoving__webhook_opportunity_status') }}
),

ranked as (
    select
        *,
        row_number() over (
            partition by source_instance_id, external_opportunity_id
            order by observed_at desc
        ) as rn
    from events
)

select
    source_instance_id || ':' || external_opportunity_id    as opportunity_key,
    entity_id,
    source_instance_id,
    external_opportunity_id,
    opportunity_status_code,
    case when opportunity_status_code = 4 then 'Booked'
         else 'status_' || opportunity_status_code end      as opportunity_status_label,
    event_type                                              as last_event_type,
    observed_at                                             as status_observed_at
from ranked
where rn = 1
