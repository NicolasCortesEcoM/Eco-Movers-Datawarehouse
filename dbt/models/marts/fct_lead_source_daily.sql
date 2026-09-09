-- Lead quality and conversion by MARKETING CHANNEL, one row per
-- (channel, line of business, day the lead arrived).
--
-- Same cohort grain as fct_agent_leads_daily, and for the same reason: a row says
-- "of the leads this channel produced on this day, here is what became of them",
-- regardless of when the outcome landed. Conversion is only answerable that way -
-- the leads that arrive on a day and the bookings that close on it are different
-- populations, and a row mixing them produces a rate nobody can reproduce.
--
-- ⚠️ THE SAME MATURITY CAVEAT APPLIES. A cohort from last week has not had time to
-- be lost yet and will always look strong. `open_leads` is carried on every row so
-- that is visible; exclude the last ~60 days from any channel comparison, or show
-- open_leads beside the rate.
--
-- WHY THIS TABLE EXISTS SEPARATELY from the agent mart: channel and agent are
-- independent attributes of the same lead. Putting both on one row multiplies the
-- grain and makes every total require a distinct-count to be correct. Two narrow
-- cohort tables answer "which agent" and "which channel" cleanly, and neither
-- answers the other's question badly.
--
-- This is the table the marketing ROI work will attach spend to: once ad cost lands
-- at (date, channel), cost-per-lead, CAC and ROAS are joins onto this, not new
-- models. `referral_is_paid` is the flag that says whether a denominator should
-- exist at all.

{{ config(materialized='table') }}

with opps as (
    select
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.created_date_local        as lead_received_date,
        -- Unmapped is a real category, not a null to be dropped. 6,196 in-scope
        -- opportunities carry a referral source the seed does not know, and they
        -- convert at 41% - hiding them would quietly remove a tenth of the funnel
        -- from every channel comparison.
        coalesce(o.referral_channel_group, '(unmapped)') as channel_group,
        o.referral_platform,
        o.referral_is_paid,
        o.is_valid_lead,
        o.is_bad_lead,
        o.is_booked,
        o.is_lost,
        o.is_open,
        o.is_cancelled,
        o.status_subcategory,
        o.estimated_final_total,
        o.invoiced_amount,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.created_date_local is not null
      and not o.is_deleted
      -- Prior-tenant guard - see dim_instance.data_valid_from.
      and o.is_in_scope
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

joined as (
    select
        o.*,
        coalesce(l.line_of_business, 'unassigned') as line_of_business
    from opps o
    left join opportunity_line l
      on  l.source_instance_id      = o.source_instance_id
      and l.external_opportunity_id = o.external_opportunity_id
),

aggregated as (
    select
        entity_id,
        channel_group,
        line_of_business,
        lead_received_date,

        -- The platform behind the channel, where every lead in the group agrees on
        -- it. Null when they do not, rather than an arbitrary pick: `Paid Search`
        -- spans Google and Bing, and silently labelling a mixed group with one of
        -- them would be a fabrication.
        case when count(distinct referral_platform) = 1
             then min(referral_platform) end          as referral_platform,
        bool_or(referral_is_paid)                     as any_paid_source,

        count(*)                                      as leads_received,
        count(*) filter (where is_valid_lead)         as valid_leads,
        count(*) filter (where is_bad_lead)           as bad_leads,

        count(*) filter (where is_booked)             as booked_leads,
        count(*) filter (where is_lost)               as lost_leads,
        count(*) filter (where is_cancelled)          as cancelled_leads,
        count(*) filter (where is_open)               as open_leads,

        -- No `quoted_leads`: see fct_agent_leads_daily for why an estimate is not
        -- evidence of a quote in this data.
        count(*) filter (where invoiced_amount > 0)         as invoiced_deals,

        sum(estimated_final_total) filter (where is_booked) as booked_estimated_value,
        sum(invoiced_amount)                                as invoiced_value,

        count(*) filter (where is_lost and status_subcategory = 'lost_competitor') as lost_to_competitor,
        count(*) filter (where is_lost and status_subcategory = 'lost_price')      as lost_on_price,
        count(*) filter (where is_lost and status_subcategory = 'lost_contact')    as lost_no_contact,

        max(synced_at)                                as synced_at
    from joined
    group by 1, 2, 3, 4
)

select
    -- Plain concatenation, readable in a BI tool. The repo has no dbt_utils
    -- dependency and one surrogate key does not justify adding it.
    a.entity_id || ':' || a.channel_group || ':' || a.line_of_business
                || ':' || to_char(a.lead_received_date, 'YYYYMMDD') as source_day_key,
    a.entity_id,
    a.channel_group,
    a.referral_platform,
    a.any_paid_source,
    a.line_of_business,
    a.lead_received_date,

    a.leads_received,
    a.valid_leads,
    a.bad_leads,
    a.booked_leads,
    a.lost_leads,
    a.cancelled_leads,
    a.open_leads,
    -- Against VALID leads, not everything received: a bad lead was never winnable,
    -- and counting it against a channel measures lead quality twice instead of once
    -- (bad_leads is already reported separately). Null, not zero, with no denominator.
    case when a.valid_leads > 0
         then round(100.0 * a.booked_leads / a.valid_leads, 1)
    end                                                             as conversion_pct,

    case when a.leads_received > 0
         then round(100.0 * a.bad_leads / a.leads_received, 1)
    end                                                             as bad_lead_pct,

    -- Realised revenue over the deals that have a figure. The estimate is zero on
    -- 45% of booked opportunities, so averaging it understates by nearly half.
    case when a.invoiced_deals > 0
         then round(a.invoiced_value / a.invoiced_deals, 2)
    end                                                             as avg_invoiced_deal_size,
    a.invoiced_deals,

    a.booked_estimated_value,
    a.invoiced_value,
    a.lost_to_competitor,
    a.lost_on_price,
    a.lost_no_contact,

    a.synced_at
from aggregated a
