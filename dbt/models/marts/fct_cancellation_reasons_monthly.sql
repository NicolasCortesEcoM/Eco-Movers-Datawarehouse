-- marts.fct_cancellation_reasons_monthly - why customers cancel, month by month.
-- Grain: one row per (entity_id, line_of_business, cancellation_reason, month the
-- cancellation HAPPENED).
--
-- PERIOD GRAIN, on purpose. The ZIP mart is a cohort (the month the lead arrived) so a
-- rate has a denominator. Reasons tell a story over time - "did price complaints rise
-- after the tariff change in May" - and that story is told by when the cancellation was
-- recorded, not by when the lead came in. A reason needs no denominator: its share is
-- of the month's cancellations (`share_of_month_pct`, computed here so a chart can use
-- it directly). Rows before 2026-01-02 fall under '(not recorded)': the Cancellations
-- report, the only source of the reason, starts there.
--
-- Each reason carries what makes it actionable:
--   how late it happens          avg / median days before the move, late share
--   what it costs                 estimated value, cancelled amount, deposits held
--   whether it comes back         rebooked_later
--   how far the move was          avg mileage - "another mover" on a 30-mile move is
--                                 a price story; on a 900-mile move it is a
--                                 long-distance capacity story
--   how big the move was          avg estimated crew and hours (move size itself is
--                                 4% populated, the crew estimate is the proxy)

{{ config(materialized='table') }}

with detail as (
    select *
    from {{ ref('int_cancellation_detail') }}
    -- A cancellation without a date cannot be placed in a month; it is still in the
    -- ZIP mart (cohort grain) and in the detail table. 4,856 rows on 2026-09-15, all
    -- pre-2026.
    where cancelled_date is not null
),

monthly as (
    select
        entity_id,
        line_of_business,
        cancellation_reason,
        date_trunc('month', cancelled_date)::date           as cancelled_month,

        count(*)                                            as cancellations,
        sum(estimated_final_total)                          as cancelled_estimated_value,
        sum(cancelled_amount)                               as cancelled_amount,

        count(*) filter (where is_late_cancellation)        as late_cancellations,
        round(100.0 * count(*) filter (where is_late_cancellation) / count(*), 1)
                                                            as late_cancellation_pct,
        round(avg(days_cancel_to_service), 1)               as avg_days_cancel_to_service,
        (percentile_cont(0.5) within group (order by days_cancel_to_service))::numeric(8,1)
                                                            as median_days_cancel_to_service,
        round(avg(days_lead_to_cancel), 1)                  as avg_days_lead_to_cancel,
        round(avg(days_booked_to_cancel), 1)                as avg_days_booked_to_cancel,

        count(*) filter (where had_deposit)                 as with_deposit,
        sum(paid_amount)                                    as deposit_amount_at_risk,
        count(*) filter (where rebooked_later)              as rebooked_later,
        count(*) filter (where move_date_was_tbd)           as move_date_was_tbd,
        count(*) filter (where is_interstate)               as interstate_moves,

        round(avg(mileage), 0)                              as avg_mileage,
        round(avg(est_crew_count), 1)                       as avg_est_crew,
        round(avg(est_time_hours), 1)                       as avg_est_hours,

        max(synced_at)                                      as synced_at
    from detail
    group by 1, 2, 3, 4
)

select
    entity_id || ':' || line_of_business || ':' || cancellation_reason
        || ':' || to_char(cancelled_month, 'YYYYMM')         as reason_month_key,
    entity_id,
    line_of_business,
    cancellation_reason,
    cancelled_month,
    cancellations,
    -- Share of the month's cancellations within the same line. Sums to 100 per
    -- (entity, line, month).
    round(100.0 * cancellations
        / sum(cancellations) over (partition by entity_id, line_of_business, cancelled_month), 1)
                                                            as share_of_month_pct,
    cancelled_estimated_value,
    cancelled_amount,
    late_cancellations,
    late_cancellation_pct,
    avg_days_cancel_to_service,
    median_days_cancel_to_service,
    avg_days_lead_to_cancel,
    avg_days_booked_to_cancel,
    with_deposit,
    deposit_amount_at_risk,
    rebooked_later,
    move_date_was_tbd,
    interstate_moves,
    avg_mileage,
    avg_est_crew,
    avg_est_hours,
    synced_at
from monthly
