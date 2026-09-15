-- marts.fct_first_contact_outcomes - does answering a lead faster change what
-- happens to it? Grain: one row per (entity_id, line_of_business, response_band,
-- received_in_business_hours, month the lead arrived).
--
-- The question Nicolas asked on 2026-09-15 was "cancellation versus time to first
-- contact". It is answered here as one of several outcomes on the same row, because
-- the same cut answers three questions at once and a manager will ask all three:
--   conversion_pct      booked / valid leads         - does speed win the deal
--   cancellation_pct    cancelled / (booked + cxl)   - does a slow start come back as
--                                                      a cancellation later
--   lost_pct            lost / valid leads
-- Bands are BUSINESS minutes (see int_first_contact_timing); the window is a var in
-- dbt_project.yml. `received_in_business_hours` is a dimension, not a filter: leads
-- that arrive at night are a different population (they self-serve online more) and
-- mixing them in would blur the speed effect.
--
-- Cohort grain on the lead's arrival month, like every other lead-outcome mart, so
-- the maturity caveat applies: last week's leads have not finished deciding.
-- Read the rates on rows with enough leads (>= 30) - the bands at the tails are thin.

{{ config(materialized='table') }}

with t as (
    select * from {{ ref('int_first_contact_timing') }}
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

joined as (
    select
        t.*,
        coalesce(l.line_of_business, 'unassigned')          as line_of_business
    from t
    left join opportunity_line l
      on  l.source_instance_id      = t.source_instance_id
      and l.external_opportunity_id = t.external_opportunity_id
)

select
    entity_id || ':' || line_of_business || ':' || response_band || ':'
        || received_in_business_hours::text || ':'
        || to_char(date_trunc('month', lead_received_date), 'YYYYMM') as contact_outcome_key,
    entity_id,
    line_of_business,
    response_band,
    received_in_business_hours,
    date_trunc('month', lead_received_date)::date           as lead_received_month,

    count(*)                                                as leads,
    count(*) filter (where is_valid_lead)                   as valid_leads,
    count(*) filter (where is_bad_lead)                     as bad_leads,
    count(*) filter (where is_booked)                       as booked_kept,
    count(*) filter (where is_cancelled)                    as cancelled,
    count(*) filter (where is_booked or is_cancelled)       as booked_or_cancelled,
    count(*) filter (where is_lost)                         as lost,
    count(*) filter (where is_open)                         as open_leads,

    case when count(*) filter (where is_valid_lead) > 0
         then round(100.0 * count(*) filter (where is_booked)
              / count(*) filter (where is_valid_lead), 1) end       as conversion_pct,
    case when count(*) filter (where is_booked or is_cancelled) > 0
         then round(100.0 * count(*) filter (where is_cancelled)
              / count(*) filter (where is_booked or is_cancelled), 1) end as cancellation_pct,
    case when count(*) filter (where is_valid_lead) > 0
         then round(100.0 * count(*) filter (where is_lost)
              / count(*) filter (where is_valid_lead), 1) end       as lost_pct,

    round(avg(business_minutes), 1)                         as avg_business_minutes,
    (percentile_cont(0.5) within group (order by business_minutes))::numeric(10,1)
                                                            as median_business_minutes,
    round(avg(clock_minutes), 1)                            as avg_clock_minutes,

    sum(invoiced_amount)                                    as invoiced_value,
    sum(estimated_final_total) filter (where is_booked)     as booked_estimated_value,
    max(synced_at)                                          as synced_at
from joined
group by 1, 2, 3, 4, 5, 6
