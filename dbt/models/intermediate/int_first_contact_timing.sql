-- marts.int_first_contact_timing - how fast each lead was answered, measured in
-- BUSINESS minutes, next to what happened to it.
-- Grain: one row per in-scope opportunity that has both a creation instant and a
-- time-to-first-contact (99% of leads since 2025; the measure comes from the Lead
-- Status report via int_report_lead_status_latest, and from Lost Leads before that).
--
-- WHY BUSINESS MINUTES. The raw measure is wall-clock minutes between the lead
-- arriving and the first reply. A lead that lands at 9 pm and is called at 8:05 the
-- next morning reads as 665 minutes - "slow" - when nobody could have answered sooner.
-- Counting only the minutes inside the sales window turns it into 5 minutes, which is
-- what the team actually controlled. Both numbers are kept: `clock_minutes` is what
-- the customer experienced, `business_minutes` is what sales is accountable for.
--
-- THE WINDOW IS CONFIGURATION, NOT CODE: vars business_hours_start / _end /
-- business_days in dbt_project.yml (Nicolas, 2026-09-15: 08:00-17:00). Change them and
-- rebuild; nothing here needs editing. Times are in the lead's branch time zone
-- (core.opportunities.timezone), so a Los Angeles lead and a Bogota-time server agree.
--
-- HOW IT IS COMPUTED. The span from arrival to first contact is cut into calendar
-- days (capped at 31 - anything longer is "over a month" whatever the exact number),
-- each day is clipped to the business window, non-business days contribute zero, and
-- the pieces are summed. A lead answered before the window opens contributes zero
-- business minutes: it was answered as soon as the day started.
--
-- Bands are in business time, sized to how a sales manager thinks: "within the
-- quarter hour", "within the hour", "same morning", "same day" (a 9 h window), "next
-- business day", "later than that".

{{ config(materialized='table') }}

{% set bh_start = var('business_hours_start') %}
{% set bh_end   = var('business_hours_end') %}
{% set bh_days  = var('business_days') %}
{% set day_len  = (bh_end - bh_start) * 60 %}

with base as (
    select
        o.opportunity_key,
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.timezone,
        o.created_at_utc at time zone o.timezone                as received_local,
        (o.created_at_utc + make_interval(mins => o.time_to_first_contact_minutes))
            at time zone o.timezone                             as first_contact_local,
        o.time_to_first_contact_minutes                         as clock_minutes,
        o.created_date_local                                    as lead_received_date,
        o.is_valid_lead, o.is_bad_lead, o.is_booked, o.is_cancelled, o.is_lost, o.is_open,
        o.estimated_final_total,
        o.invoiced_amount,
        o.sales_assignee_name,
        o.referral_source_clean                                 as referral_source,
        o.referral_campaign_group,
        o.referral_is_paid,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.is_in_scope
      and not o.is_deleted
      and o.created_at_utc is not null
      and o.time_to_first_contact_minutes is not null
      and o.time_to_first_contact_minutes >= 0
),

-- One row per (lead, calendar day the span touches), capped at 31 days.
days as (
    select
        b.opportunity_key,
        b.received_local,
        b.first_contact_local,
        d::date                                                 as day
    from base b
    cross join lateral generate_series(
        b.received_local::date,
        least(b.first_contact_local::date, b.received_local::date + 31),
        interval '1 day'
    ) as d
),

per_day as (
    select
        opportunity_key,
        greatest(0, extract(epoch from (
            least(first_contact_local, day + interval '{{ bh_end }} hours')
            - greatest(received_local, day + interval '{{ bh_start }} hours')
        )) / 60.0)                                              as minutes
    from days
    where extract(isodow from day) in ({{ bh_days | join(', ') }})
),

business as (
    select opportunity_key, round(sum(minutes))::int            as business_minutes
    from per_day
    group by 1
)

select
    b.opportunity_key,
    b.entity_id,
    b.source_instance_id,
    b.external_opportunity_id,
    b.lead_received_date,
    b.received_local,
    b.first_contact_local,
    -- Was the lead received inside the sales window at all
    (extract(isodow from b.received_local) in ({{ bh_days | join(', ') }})
     and extract(hour from b.received_local) >= {{ bh_start }}
     and extract(hour from b.received_local) <  {{ bh_end }})   as received_in_business_hours,
    extract(isodow from b.received_local)::int                  as received_isodow,
    extract(hour   from b.received_local)::int                  as received_hour_local,

    b.clock_minutes,
    coalesce(bm.business_minutes, 0)                            as business_minutes,
    case
        when coalesce(bm.business_minutes, 0) <= 15                 then '01 <= 15 min'
        when bm.business_minutes <= 60                              then '02 16-60 min'
        when bm.business_minutes <= 240                             then '03 1-4 h'
        when bm.business_minutes <= {{ day_len }}                   then '04 same business day'
        when bm.business_minutes <= {{ day_len * 2 }}               then '05 next business day'
        else                                                             '06 2+ business days'
    end                                                         as response_band,

    b.is_valid_lead, b.is_bad_lead, b.is_booked, b.is_cancelled, b.is_lost, b.is_open,
    b.estimated_final_total,
    b.invoiced_amount,
    b.sales_assignee_name,
    b.referral_source,
    b.referral_campaign_group,
    b.referral_is_paid,
    b.synced_at
from base b
left join business bm on bm.opportunity_key = b.opportunity_key
