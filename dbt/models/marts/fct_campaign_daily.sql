-- marts.fct_campaign_daily - lead outcomes per MARKETING CAMPAIGN, at two levels.
-- Grain: one row per (entity_id, campaign_group, campaign, line_of_business, day the
-- lead arrived).
--
-- THE TABLE MARKETING SPEND ATTACHES TO. fct_lead_source_daily is keyed on the
-- channel (Paid Search, Paid Social, GBP...), which is the right level for "is paid
-- search worth it" and the wrong level for "is the Snohomish campaign worth it".
-- Cost arrives per campaign, so the join has to happen per campaign. That is this
-- table's whole reason to exist.
--
-- TWO LEVELS, ON EVERY ROW. `campaign` is the individual CRM source
-- (`Google Ads Snohomish`); `campaign_group` is the family it rolls up to
-- (`Google Ads`). Both are here because both questions get asked and a single column
-- can only answer one. Sum over `campaign` to get the family; filter by `campaign` to
-- get the campaign. Neither requires a distinct-count.
--
-- HOW COST WILL BE SPLIT ACROSS LINES OF BUSINESS - the rule, set by Nicolas on
-- 2026-09-10 and not up for renegotiation in the model:
--
--   Cost is attributed PER LEAD, not per the campaign's nominal line. A campaign
--   considered "Local" that spent $100 and produced 2 Local leads and 2 Long Distance
--   leads gives $50 to each line. The split is proportional to the leads each line
--   actually received from that source, across BOTH instances.
--
-- This grain is built for exactly that. A row already holds the leads one line
-- received from one campaign on one day; `campaign_day_leads_total` holds what the
-- campaign produced across all lines that day. So when spend lands at
-- (campaign, day):
--
--   attributed_cost = campaign_spend * leads_received / campaign_day_leads_total
--
-- and it sums back to the campaign's spend exactly, by construction. Spend at a
-- coarser grain (a month) recomputes the same share from the daily rows; the rule
-- does not change, only the window.
--
-- COMMERCIAL IS THE EXCEPTION, and it is not special-cased here. Commercial is
-- measured by its own campaigns (`Bing Ads Commercial`, `Eco Commercial (Google
-- Ads)`), not by line of business, so for those campaigns the consumer reads the
-- campaign row and ignores the line split. Nothing in this model needs to know that;
-- it is a reporting choice, and baking it in would make the Local/LD split wrong the
-- day a commercial campaign produces a residential lead.
--
-- Same cohort grain and the same maturity caveat as the other two cohort marts: a
-- lead from last week has not had time to be lost, so `open_leads` travels on every
-- row. Excludes prior-tenant rows via core.opportunities.is_in_scope.

{{ config(materialized='table') }}

with opps as (
    select
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.created_date_local                                as lead_received_date,
        -- Two levels. The individual campaign falls back to the raw CRM string so a
        -- source the seed has not mapped yet is still visible, under its own name,
        -- rather than vanishing. '(unmapped)' is the family for those.
        coalesce(o.referral_source_clean, o.referral_source, '(none)') as campaign,
        coalesce(o.referral_campaign_group, '(unmapped)')   as campaign_group,
        o.referral_channel_group                            as channel_group,
        o.referral_platform,
        o.referral_is_paid,
        o.is_valid_lead,
        o.is_bad_lead,
        o.is_booked,
        o.is_lost,
        o.is_cancelled,
        o.is_open,
        o.estimated_final_total,
        o.invoiced_amount,
        o.status_subcategory,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.created_date_local is not null
      and not o.is_deleted
      and o.is_in_scope
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

joined as (
    select
        o.*,
        coalesce(l.line_of_business, 'unassigned')         as line_of_business
    from opps o
    left join opportunity_line l
      on  l.source_instance_id      = o.source_instance_id
      and l.external_opportunity_id = o.external_opportunity_id
),

aggregated as (
    select
        entity_id,
        campaign_group,
        campaign,
        line_of_business,
        lead_received_date,

        -- Attributes of the campaign, constant within it. Carried so a consumer
        -- does not need a second join to know whether spend should exist at all.
        min(channel_group)                                  as channel_group,
        min(referral_platform)                              as referral_platform,
        bool_or(coalesce(referral_is_paid, false))          as is_paid,

        count(*)                                            as leads_received,
        count(*) filter (where is_valid_lead)               as valid_leads,
        count(*) filter (where is_bad_lead)                 as bad_leads,
        count(*) filter (where is_booked)                   as booked_leads,
        count(*) filter (where is_lost)                     as lost_leads,
        count(*) filter (where is_cancelled)                as cancelled_leads,
        count(*) filter (where is_open)                     as open_leads,

        sum(estimated_final_total) filter (where is_booked) as booked_estimated_value,
        sum(invoiced_amount)                                as invoiced_value,
        count(*) filter (where invoiced_amount > 0)         as invoiced_deals,

        count(*) filter (where is_lost and status_subcategory = 'lost_competitor') as lost_to_competitor,
        count(*) filter (where is_lost and status_subcategory = 'lost_price')      as lost_on_price,

        max(synced_at)                                      as synced_at
    from joined
    group by 1, 2, 3, 4, 5
)

select
    entity_id || ':' || campaign || ':' || line_of_business
        || ':' || to_char(lead_received_date, 'YYYYMMDD')  as campaign_day_key,
    entity_id,
    campaign_group,
    campaign,
    line_of_business,
    lead_received_date,
    channel_group,
    referral_platform,
    is_paid,

    leads_received,
    -- What the campaign produced that day ACROSS ALL LINES. The denominator of the
    -- cost split: this row's share of the campaign's spend is
    -- leads_received / campaign_day_leads_total.
    sum(leads_received) over (partition by entity_id, campaign, lead_received_date)
                                                            as campaign_day_leads_total,
    round(100.0 * leads_received
        / sum(leads_received) over (partition by entity_id, campaign, lead_received_date), 2)
                                                            as line_share_pct,

    valid_leads,
    bad_leads,
    booked_leads,
    lost_leads,
    cancelled_leads,
    open_leads,

    case when valid_leads > 0
         then round(100.0 * booked_leads / valid_leads, 1) end as conversion_pct,
    case when leads_received > 0
         then round(100.0 * bad_leads / leads_received, 1) end as bad_lead_pct,
    case when (booked_leads + cancelled_leads) > 0
         then round(100.0 * cancelled_leads / (booked_leads + cancelled_leads), 1)
    end                                                     as cancellation_pct,

    booked_estimated_value,
    invoiced_value,
    invoiced_deals,
    case when invoiced_deals > 0
         then round(invoiced_value / invoiced_deals, 2) end as avg_invoiced_deal_size,

    lost_to_competitor,
    lost_on_price,
    synced_at
from aggregated
