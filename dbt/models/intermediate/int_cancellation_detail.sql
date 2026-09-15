-- marts.int_cancellation_detail - one row per cancelled opportunity, with everything a
-- manager would want to cut a cancellation by. The base both cancellation marts read
-- (by ZIP, by reason) and the table to open in Metabase when a number needs a face.
-- Grain: one row per cancelled, in-scope, non-deleted opportunity (6,358 on 2026-09-15).
--
-- WHY A DETAIL TABLE AND NOT JUST TWO AGGREGATES. Cancellations are rare enough (1,450
-- in 2026) that any two-dimensional cut runs out of rows fast. A single wide row lets
-- an analyst pick the cut - ZIP x reason, reason x days-before-move, agent x deposit -
-- without a model per question. The two marts are the two cuts Nicolas asked for; this
-- is what makes the third one a query instead of a ticket.
--
-- WHAT IS MEASURED, and where it comes from:
--   Geography      the PRIMARY job (earliest service date) of the opportunity: origin
--                  and destination ZIP / city / state, origin type, mileage. 99% of
--                  cancellations have a job with an origin ZIP.
--   Reason         core.opportunities.cancellation_reason, from the Cancellations
--                  report - 100% since 2026-01-02, 24% before (window of the report).
--   Timing         days from lead to cancel; from JOB booking to cancel (the job's
--                  booked date, 79% - opportunities.booked_date_local is nearly empty);
--                  and days from cancel to the planned move, the operational one.
--   Late           is_late_cancellation = cancelled within 2 days of the service date
--                  or after it. For a mover that is the cancellation that already cost
--                  a crew and a truck. 35% of 2026 cancellations, measured.
--   Value          estimated_final_total (60% populated); cancelled_amount from the
--                  report (2026+).
--   Deposit        payments landed against the opportunity - refund exposure, and a
--                  proxy for how committed the customer was. ZERO today (2026-09-15):
--                  no cancelled opportunity has a payment in either payments table.
--                  Either deposits are not taken or refunded payments drop out of the
--                  Payments report; the Refunds report (Phase D) settles which.
--   Win-back       the same CRM customer booked a later opportunity: 126 of 6,358 (2%).
--
-- NOT MEASURED: move size. Populated on 4% of cancelled opportunities and 5% of their
-- jobs; the crew / truck / hours estimates are the usable proxy for size.

with cancelled as (
    select
        o.opportunity_key,
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.external_customer_id,
        o.quote_number,
        o.customer_name,
        o.branch_name,
        o.sales_assignee_name,
        o.referral_source_clean                             as referral_source,
        o.referral_campaign_group,
        o.referral_channel_group,
        o.referral_is_paid,
        o.created_date_local                                as lead_received_date,
        o.service_date,
        o.cancelled_date_local                              as cancelled_date,
        coalesce(nullif(trim(o.cancellation_reason), ''), '(not recorded)') as cancellation_reason,
        o.estimated_final_total,
        o.cancelled_amount,
        o.time_to_first_contact_minutes,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.is_cancelled
      and not o.is_deleted
      and o.is_in_scope
),

-- The primary job: earliest service date, then lowest job id for determinism.
primary_job as (
    select distinct on (j.source_instance_id, j.external_opportunity_id)
        j.source_instance_id,
        j.external_opportunity_id,
        j.external_job_id,
        j.job_number,
        j.job_type_name,
        j.service_type_name,
        j.origin_zip, j.origin_city, j.origin_state, j.origin_type,
        j.destination_zip, j.destination_city, j.destination_state, j.destination_type,
        j.origin_to_destination_mileage                     as mileage,
        j.est_crew_count, j.est_truck_count, j.est_time_hours,
        j.move_date_is_tbd,
        j.job_booked_date_local,
        j.job_created_date_local
    from {{ ref('jobs') }} j
    where j.external_opportunity_id is not null
    order by j.source_instance_id, j.external_opportunity_id, j.service_date nulls last, j.external_job_id
),

job_count as (
    select source_instance_id, external_opportunity_id, count(*) as job_count
    from {{ ref('jobs') }}
    where external_opportunity_id is not null
    group by 1, 2
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

agents as (
    select source_agent_name, agent_name, is_sales_agent
    from {{ ref('agents') }}
),

-- Money received against the opportunity. Payments dated before the cancellation are
-- a deposit at risk of refund; anything else is still "the customer had paid".
deposits as (
    select
        p.source_instance_id,
        p.external_opportunity_id,
        sum(p.payment_amount)                               as paid_amount,
        min(p.payment_date_local)                           as first_payment_date
    from {{ ref('payments') }} p
    where p.external_opportunity_id is not null
    group by 1, 2
),

-- Win-back: the same customer booked again after the cancellation.
later_bookings as (
    select
        source_instance_id,
        external_customer_id,
        created_date_local                                  as booked_lead_date
    from {{ ref('opportunities') }}
    where is_booked and is_in_scope and not is_deleted
      and external_customer_id is not null
),

rebooked as (
    select
        c.opportunity_key,
        min(b.booked_lead_date)                             as rebooked_lead_date
    from cancelled c
    join later_bookings b
      on  b.source_instance_id    = c.source_instance_id
      and b.external_customer_id  = c.external_customer_id
      and b.booked_lead_date      > coalesce(c.cancelled_date, c.lead_received_date)
    group by 1
)

select
    c.opportunity_key,
    c.entity_id,
    c.source_instance_id,
    c.external_opportunity_id,
    c.quote_number,
    c.customer_name,
    c.branch_name,
    coalesce(a.agent_name, nullif(trim(c.sales_assignee_name), ''), 'unassigned') as agent_name,
    coalesce(l.line_of_business, 'unassigned')              as line_of_business,
    l.is_provisional_line,
    c.referral_source,
    c.referral_campaign_group,
    c.referral_channel_group,
    c.referral_is_paid,

    -- Dates
    c.lead_received_date,
    pj.job_booked_date_local                                as booked_date,
    c.cancelled_date,
    c.service_date,
    coalesce(pj.move_date_is_tbd, false)                    as move_date_was_tbd,

    -- Timing. Null when the cancellation date is unknown (pre-2026 report window).
    (c.cancelled_date - c.lead_received_date)               as days_lead_to_cancel,
    (c.cancelled_date - pj.job_booked_date_local)           as days_booked_to_cancel,
    (c.service_date - c.cancelled_date)                     as days_cancel_to_service,
    case
        when c.cancelled_date is null                        then null
        when c.service_date - c.cancelled_date < 0           then 'after service date'
        when c.service_date - c.cancelled_date <= 1          then '0-1 day'
        when c.service_date - c.cancelled_date <= 3          then '2-3 days'
        when c.service_date - c.cancelled_date <= 7          then '4-7 days'
        when c.service_date - c.cancelled_date <= 14         then '8-14 days'
        else                                                      '15+ days'
    end                                                     as cancel_timing_band,
    -- Within 48 h of the move, or after it: the crew and truck were already committed.
    case when c.cancelled_date is null then null
         else (c.service_date - c.cancelled_date) <= 2 end   as is_late_cancellation,

    -- Reason
    c.cancellation_reason,
    (c.cancellation_reason = 'Decided to go with another mover')  as is_lost_to_competitor,
    (c.cancellation_reason = 'Price was to high')                 as is_lost_on_price,

    -- Geography and job shape, from the primary job
    pj.origin_zip, pj.origin_city, pj.origin_state, pj.origin_type,
    pj.destination_zip, pj.destination_city, pj.destination_state, pj.destination_type,
    (pj.origin_state is distinct from pj.destination_state)  as is_interstate,
    pj.mileage,
    case
        when pj.mileage is null     then null
        when pj.mileage <  50       then '< 50 mi'
        when pj.mileage <  150      then '50-149 mi'
        when pj.mileage <  500      then '150-499 mi'
        else                             '500+ mi'
    end                                                     as distance_band,
    pj.job_type_name,
    pj.service_type_name,
    pj.est_crew_count,
    pj.est_truck_count,
    pj.est_time_hours,
    coalesce(jc.job_count, 0)                               as job_count,

    -- Value
    c.estimated_final_total,
    c.cancelled_amount,
    coalesce(d.paid_amount, 0)                              as paid_amount,
    (coalesce(d.paid_amount, 0) > 0)                        as had_deposit,
    d.first_payment_date,

    -- Win-back
    (r.rebooked_lead_date is not null)                      as rebooked_later,
    r.rebooked_lead_date,
    (r.rebooked_lead_date - coalesce(c.cancelled_date, c.lead_received_date)) as days_to_rebook,

    c.time_to_first_contact_minutes,
    c.synced_at
from cancelled c
left join primary_job pj
       on  pj.source_instance_id      = c.source_instance_id
       and pj.external_opportunity_id = c.external_opportunity_id
left join job_count jc
       on  jc.source_instance_id      = c.source_instance_id
       and jc.external_opportunity_id = c.external_opportunity_id
left join opportunity_line l
       on  l.source_instance_id       = c.source_instance_id
       and l.external_opportunity_id  = c.external_opportunity_id
left join agents a
       on {{ norm_text('a.source_agent_name') }} = {{ norm_text('c.sales_assignee_name') }}
left join deposits d
       on  d.source_instance_id       = c.source_instance_id
       and d.external_opportunity_id  = c.external_opportunity_id
left join rebooked r
       on r.opportunity_key = c.opportunity_key
