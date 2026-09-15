-- marts.fct_booking_survival - what share of bookings is still alive N days after
-- being booked. Grain: one row per (entity_id, line_of_business, booking_lead_band,
-- booked_year, horizon_days).
--
-- THE QUESTION (Nicolas, 2026-09-15): "what percentage of bookings survives 7, 14, 30
-- days - so we know when to call a customer to reconfirm the move." The answer is a
-- survival curve, and a survival curve has two rules that a plain percentage breaks:
--
--   1. A booking only counts at horizon h if it COULD have cancelled by h: it had at
--      least h days between booking and move (`booking_lead_days >= h`) and those h
--      days have already elapsed. A booking that moved on day 5 is not a survivor at
--      day 7 - it left the population. A booking made yesterday is not a survivor at
--      day 30 - it has not been tested yet.
--   2. Cancellations whose date is unknown (pre-2026) cannot be placed, so they are
--      out of the curve entirely and counted in `cancellations_timing_unknown` on the
--      row instead. Read 2026 for the curve; earlier years understate cancellation.
--
-- `survival_pct` is cumulative: alive at h over at risk at h. `hazard_pct` is the
-- share of bookings alive at the previous horizon that cancelled between the two -
-- the "when to call" number: the window with the highest hazard is where a
-- reconfirmation call prevents the most cancellations.
--
-- `booking_lead_band` (days between booking and move) is a dimension because it is
-- Nicolas's hypothesis: bookings made far ahead cancel more. Sum at_risk and
-- cancelled_by_horizon across bands to get the overall curve; never average the pcts.
-- Horizons are the var `survival_horizons` in dbt_project.yml.

{{ config(materialized='table') }}

{% set horizons = var('survival_horizons') %}

with bookings as (
    select *
    from {{ ref('int_booking_detail') }}
    where booked_date is not null
      and service_date is not null
      and booking_lead_days >= 0
),

horizons as (
    select horizon_days,
           lag(horizon_days) over (order by horizon_days)   as prev_horizon_days
    from unnest(array[{{ horizons | join(', ') }}]) as horizon_days
),

at_risk as (
    -- The population at horizon h: bookings that had at least h days between booking
    -- and move, and whose h-th day has already passed. A cancellation inside those h
    -- days is IN the population (it had the chance) - as a cancellation.
    select
        b.entity_id,
        b.line_of_business,
        b.booking_lead_band,
        extract(year from b.booked_date)::int               as booked_year,
        h.horizon_days,
        h.prev_horizon_days,
        b.opportunity_key,
        b.is_cancelled,
        b.cancel_timing_known,
        b.days_booked_to_cancel
    from bookings b
    cross join horizons h
    where b.booking_lead_days >= h.horizon_days
      and b.booked_date + h.horizon_days <= current_date
),

agg as (
    select
        entity_id, line_of_business, booking_lead_band, booked_year, horizon_days,
        prev_horizon_days,
        count(*) filter (where cancel_timing_known)                                as at_risk,
        count(*) filter (where is_cancelled and cancel_timing_known
                          and days_booked_to_cancel <= horizon_days)             as cancelled_by_horizon,
        -- Same population, previous horizon: the right base for the hazard.
        count(*) filter (where is_cancelled and cancel_timing_known
                          and days_booked_to_cancel <= prev_horizon_days)        as cancelled_by_prev,
        count(*) filter (where is_cancelled and not cancel_timing_known)         as cancellations_timing_unknown
    from at_risk
    group by 1, 2, 3, 4, 5, 6
),

curve as (
    select *, at_risk - cancelled_by_horizon as alive_at_horizon
    from agg
)

select
    entity_id || ':' || line_of_business || ':' || coalesce(booking_lead_band, '(none)')
        || ':' || booked_year || ':' || horizon_days                              as survival_key,
    entity_id,
    line_of_business,
    booking_lead_band,
    booked_year,
    horizon_days,
    at_risk,
    cancelled_by_horizon,
    alive_at_horizon,
    case when at_risk > 0
         then round(100.0 * alive_at_horizon / at_risk, 1) end                     as survival_pct,
    -- Cancelled in (previous horizon, this horizon], over those alive at the previous
    -- horizon and still at risk now.
    (cancelled_by_horizon - coalesce(cancelled_by_prev, 0))                        as cancelled_in_window,
    case when (at_risk - coalesce(cancelled_by_prev, 0)) > 0 and prev_horizon_days is not null
         then round(100.0 * (cancelled_by_horizon - coalesce(cancelled_by_prev, 0))
              / (at_risk - coalesce(cancelled_by_prev, 0)), 2) end                  as hazard_pct,
    prev_horizon_days                                                              as window_from_day,
    cancellations_timing_unknown,
    now()                                                                          as synced_at
from curve
