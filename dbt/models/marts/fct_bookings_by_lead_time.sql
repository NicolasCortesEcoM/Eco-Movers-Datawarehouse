-- marts.fct_bookings_by_lead_time - do bookings made far ahead cancel more?
-- Grain: one row per (entity_id, line_of_business, booking_lead_band, month booked).
--
-- Nicolas's hypothesis (2026-09-15): the older the booking, the likelier the
-- cancellation. This is the direct test - cancellation rate by how many days ahead
-- of the move the booking was made - while fct_booking_survival is the time-based
-- view of the same population. Same denominator rule as everywhere:
-- cancellation_pct = cancelled / (booked + cancelled). Cancellations without a
-- known date still count here (they are a cancellation whatever the timing), so this
-- table is complete for 2023-2026 where the survival curve is 2026-only.
-- Recent months are immature: a booking made last week has not had time to cancel.

{{ config(materialized='table') }}

select
    entity_id || ':' || line_of_business || ':' || coalesce(booking_lead_band, '(none)')
        || ':' || to_char(date_trunc('month', booked_date), 'YYYYMM')  as lead_time_month_key,
    entity_id,
    line_of_business,
    coalesce(booking_lead_band, '(no dates)')               as booking_lead_band,
    date_trunc('month', booked_date)::date                  as booked_month,

    count(*)                                                as bookings,
    count(*) filter (where not is_cancelled)                as booked_kept,
    count(*) filter (where is_cancelled)                    as cancelled,
    round(100.0 * count(*) filter (where is_cancelled) / count(*), 1) as cancellation_pct,

    count(*) filter (where is_late_cancellation)            as late_cancellations,
    round(avg(days_booked_to_cancel), 1)                    as avg_days_booked_to_cancel,
    (percentile_cont(0.5) within group (order by days_booked_to_cancel))::numeric(8,1)
                                                            as median_days_booked_to_cancel,
    round(avg(booking_lead_days), 1)                        as avg_booking_lead_days,

    sum(estimated_final_total) filter (where is_cancelled)  as cancelled_estimated_value,
    sum(estimated_final_total) filter (where not is_cancelled) as kept_estimated_value,
    max(synced_at)                                          as synced_at
from {{ ref('int_booking_detail') }}
where booked_date is not null
group by 1, 2, 3, 4, 5
