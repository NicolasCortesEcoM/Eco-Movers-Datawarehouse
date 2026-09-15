-- marts.fct_cancellations_by_zip - where cancellations happen, WITH the denominator.
-- Grain: one row per (entity_id, line_of_business, origin_state, origin_city,
-- origin_zip, month the lead arrived).
--
-- THE DENOMINATOR IS THE WHOLE POINT. A ZIP with 2 cancellations out of 2 bookings and
-- a ZIP with 2 out of 200 have the same count and opposite meanings. Every row carries
-- `booked_or_cancelled` so the rate can be computed at any roll-up (a city, a quarter,
-- a line) by summing numerators and denominators - never by averaging the row rates.
--
-- Formula, same as sales_agent_daily_v1 (Nicolas, 2026-09-10):
--   cancellation_pct = cancellations / (booked + cancellations)
-- because a cancellation REPLACES the booked state, so "booked" alone undercounts what
-- was won. Cohort grain: the month the LEAD arrived, so a lead and its outcome sit in
-- the same row. Recent months are immature - a booking from last week has not had
-- time to cancel.
--
-- Geography is the ORIGIN of the primary job (earliest service date), for both the
-- kept bookings and the cancellations, so numerator and denominator are built the same
-- way. Bookings with no job (rare) fall under '(no job)'. City and state are the most
-- common spelling seen for that ZIP - the CRM holds "Seattle", "SEATTLE" and
-- "Seattle " for one ZIP, and a ZIP has exactly one state and, in practice, one city.
--
-- Reasons travel as columns, not rows, so a manager reads one line per ZIP. The share
-- of a reason within the ZIP is that column over `cancellations`.
--
-- MINIMUM ROWS FOR A RATE TO MEAN ANYTHING: none is enforced here - filter on
-- booked_or_cancelled >= 20 in the report before ranking ZIPs by rate.

{{ config(materialized='table') }}

with primary_job as (
    select distinct on (j.source_instance_id, j.external_opportunity_id)
        j.source_instance_id,
        j.external_opportunity_id,
        j.origin_zip
    from {{ ref('jobs') }} j
    where j.external_opportunity_id is not null
    order by j.source_instance_id, j.external_opportunity_id, j.service_date nulls last, j.external_job_id
),

-- The denominator: everything that was won at some point.
won as (
    select
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.created_date_local                                as lead_received_date,
        o.is_cancelled,
        o.estimated_final_total,
        o.synced_at
    from {{ ref('opportunities') }} o
    where (o.is_booked or o.is_cancelled)
      and o.created_date_local is not null
      and not o.is_deleted
      and o.is_in_scope
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

detail as (
    select * from {{ ref('int_cancellation_detail') }}
),

-- One city and one state per ZIP: the most frequent spelling across all jobs.
zip_place as (
    select
        origin_zip,
        mode() within group (order by initcap(trim(origin_city)))  as origin_city,
        mode() within group (order by upper(trim(origin_state)))   as origin_state
    from {{ ref('jobs') }}
    where origin_zip is not null
    group by 1
),

base as (
    select
        w.entity_id,
        coalesce(l.line_of_business, 'unassigned')          as line_of_business,
        coalesce(zp.origin_state, '(no job)')               as origin_state,
        coalesce(zp.origin_city,  '(no job)')               as origin_city,
        coalesce(pj.origin_zip,   '(no job)')               as origin_zip,
        date_trunc('month', w.lead_received_date)::date     as lead_received_month,
        w.is_cancelled,
        w.estimated_final_total,
        d.is_late_cancellation,
        d.cancellation_reason,
        d.had_deposit,
        d.paid_amount,
        d.rebooked_later,
        d.days_cancel_to_service,
        d.cancelled_amount,
        greatest(w.synced_at, d.synced_at)                  as synced_at
    from won w
    left join primary_job pj
           on  pj.source_instance_id      = w.source_instance_id
           and pj.external_opportunity_id = w.external_opportunity_id
    left join zip_place zp
           on zp.origin_zip = pj.origin_zip
    left join opportunity_line l
           on  l.source_instance_id       = w.source_instance_id
           and l.external_opportunity_id  = w.external_opportunity_id
    left join detail d
           on  d.source_instance_id       = w.source_instance_id
           and d.external_opportunity_id  = w.external_opportunity_id
)

select
    entity_id || ':' || line_of_business || ':' || origin_zip
        || ':' || to_char(lead_received_month, 'YYYYMM')     as zip_month_key,
    entity_id,
    line_of_business,
    origin_state,
    origin_city,
    origin_zip,
    lead_received_month,

    count(*)                                                as booked_or_cancelled,
    count(*) filter (where not is_cancelled)                as booked_kept,
    count(*) filter (where is_cancelled)                    as cancellations,
    round(100.0 * count(*) filter (where is_cancelled) / count(*), 1)
                                                            as cancellation_pct,

    sum(estimated_final_total) filter (where not is_cancelled) as kept_estimated_value,
    sum(estimated_final_total) filter (where is_cancelled)     as cancelled_estimated_value,
    sum(cancelled_amount)                                   as cancelled_amount,

    -- Operational cost: cancelled within 48 h of the move or after it.
    count(*) filter (where is_late_cancellation)            as late_cancellations,
    case when count(*) filter (where is_cancelled and is_late_cancellation is not null) > 0
         then round(100.0 * count(*) filter (where is_late_cancellation)
              / count(*) filter (where is_cancelled and is_late_cancellation is not null), 1)
    end                                                     as late_cancellation_pct,
    round(avg(days_cancel_to_service) filter (where is_cancelled), 1)
                                                            as avg_days_cancel_to_service,

    -- Reasons as columns. Only populated where the report window covers the row
    -- (2026+); '(not recorded)' is the rest.
    count(*) filter (where cancellation_reason = 'Service no longer needed')             as reason_no_longer_needed,
    count(*) filter (where cancellation_reason = 'Decided to go with another mover')     as reason_other_mover,
    count(*) filter (where cancellation_reason = 'Price was to high')                    as reason_price,
    count(*) filter (where cancellation_reason = 'Unable to confirm move date')          as reason_date_unconfirmed,
    count(*) filter (where cancellation_reason = 'Didn''t close on house')               as reason_house_not_closed,
    count(*) filter (where cancellation_reason = 'Unable to contact client on move day') as reason_no_contact_move_day,
    count(*) filter (where cancellation_reason = 'No Availability')                      as reason_no_availability,
    count(*) filter (where is_cancelled and cancellation_reason = '(not recorded)')      as reason_not_recorded,

    count(*) filter (where is_cancelled and had_deposit)    as cancellations_with_deposit,
    sum(paid_amount) filter (where is_cancelled)            as deposit_amount_at_risk,
    count(*) filter (where is_cancelled and rebooked_later) as rebooked_later,

    max(synced_at)                                          as synced_at
from base
group by 1, 2, 3, 4, 5, 6, 7
