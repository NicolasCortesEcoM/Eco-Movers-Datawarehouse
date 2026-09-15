-- marts.int_booking_detail - every booking ever won, with when it was booked, when
-- (if) it was cancelled, and how long it was exposed to cancellation.
-- Grain: one row per in-scope opportunity that is booked or was cancelled.
--
-- THE BOOKING DATE HAS THREE SOURCES, and the coverage is uneven enough that the
-- source travels on the row:
--   job         core.jobs.job_booked_date_local (All Jobs report). Complete for
--               2023-2025 bookings, but SmartMoving blanks it on cancelled jobs in the
--               current-year report, so 2026 cancellations mostly lack it.
--   report      core.opportunities.booked_date_local (Booked report). Only while the
--               opportunity is still booked - a cancellation leaves the report.
--   webhook     first opportunity-status webhook that showed a booked status, since
--               2026-07-22. Complete for anything booked after that date.
--   lead_proxy  the day the LEAD arrived. Measured 2026-09-15 on 6,362 bookings with
--               a real booking date: median gap lead -> booking is 0 days, p75 is 2.
--               Used only when nothing else exists, which in practice means 2026
--               cancellations (999 of 1,452 had no other source). It overstates
--               days-booked-to-cancel by at most a couple of days; without it the
--               2026 survival curve dropped two thirds of its cancellations and read
--               95% where the truth is lower.
-- Priority job > report > webhook > lead_proxy; the source travels on every row, so a
-- consumer can exclude the proxy rows and see how much they move the number.
--
-- EXPOSURE. A booking can cancel from the day it is booked until the move happens.
-- `exposure_days` = days from booking to the earlier of the service date and the
-- cancellation; `observable_days` additionally stops at today, because a booking
-- made yesterday for next month has not had 30 days to cancel yet. Survival at a
-- horizon h counts only bookings with observable_days >= h (still at risk at h) - a
-- booking that completed on day 5 is not a "survivor at day 7", it is out of the
-- population.
--
-- Cancellations WITHOUT a cancellation date (pre-2026, the Cancellations report's
-- window) cannot be placed on the curve: `cancel_timing_known = false`. They stay
-- here for counts and are excluded from survival, and the mart says how many.

with won as (
    select
        o.opportunity_key,
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.created_date_local                                as lead_received_date,
        o.service_date,
        o.booked_date_local                                 as report_booked_date,
        o.cancelled_date_local                              as cancelled_date,
        o.is_cancelled,
        o.estimated_final_total,
        o.invoiced_amount,
        o.sales_assignee_name,
        o.referral_source_clean                             as referral_source,
        o.referral_campaign_group,
        o.synced_at
    from {{ ref('opportunities') }} o
    where (o.is_booked or o.is_cancelled)
      and not o.is_deleted
      and o.is_in_scope
),

job_booked as (
    select source_instance_id, external_opportunity_id,
           min(job_booked_date_local)                       as job_booked_date
    from {{ ref('jobs') }}
    where job_booked_date_local is not null
    group by 1, 2
),

webhook_booked as (
    select
        s.source_instance_id,
        s.external_opportunity_id,
        min(s.observed_at at time zone 'America/Los_Angeles')::date as webhook_booked_date
    from {{ ref('stg_smartmoving__webhook_opportunity_status') }} s
    join {{ ref('dim_opportunity_status') }} d on d.status_code = s.opportunity_status_code
    where d.is_booked
    group by 1, 2
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

resolved as (
    select
        w.*,
        coalesce(l.line_of_business, 'unassigned')          as line_of_business,
        coalesce(jb.job_booked_date, w.report_booked_date, wb.webhook_booked_date,
                 w.lead_received_date)                        as booked_date,
        case
            when jb.job_booked_date is not null     then 'job'
            when w.report_booked_date is not null   then 'report'
            when wb.webhook_booked_date is not null then 'webhook'
            when w.lead_received_date is not null   then 'lead_proxy'
        end                                                 as booked_date_source
    from won w
    left join job_booked jb
           on jb.source_instance_id = w.source_instance_id
          and jb.external_opportunity_id = w.external_opportunity_id
    left join webhook_booked wb
           on wb.source_instance_id = w.source_instance_id
          and wb.external_opportunity_id = w.external_opportunity_id
    left join opportunity_line l
           on l.source_instance_id = w.source_instance_id
          and l.external_opportunity_id = w.external_opportunity_id
)

select
    opportunity_key,
    entity_id,
    source_instance_id,
    external_opportunity_id,
    line_of_business,
    lead_received_date,
    booked_date,
    booked_date_source,
    service_date,
    cancelled_date,
    is_cancelled,
    (not is_cancelled or cancelled_date is not null)        as cancel_timing_known,

    (service_date - booked_date)                            as booking_lead_days,
    case
        when booked_date is null or service_date is null   then null
        when service_date - booked_date < 0                then 'booked after move date'
        when service_date - booked_date <= 6               then '0-6 days'
        when service_date - booked_date <= 13              then '7-13 days'
        when service_date - booked_date <= 29              then '14-29 days'
        when service_date - booked_date <= 59              then '30-59 days'
        else                                                    '60+ days'
    end                                                     as booking_lead_band,

    (cancelled_date - booked_date)                          as days_booked_to_cancel,
    (service_date - cancelled_date)                         as days_cancel_to_service,
    case when cancelled_date is null then null
         else (service_date - cancelled_date) <= 2 end       as is_late_cancellation,

    -- Days the booking was exposed to cancellation, and how many of those are
    -- observable today.
    (least(service_date, coalesce(cancelled_date, service_date)) - booked_date)  as exposure_days,
    (least(service_date, coalesce(cancelled_date, service_date), current_date) - booked_date)
                                                            as observable_days,

    estimated_final_total,
    invoiced_amount,
    sales_assignee_name,
    referral_source,
    referral_campaign_group,
    synced_at
from resolved
