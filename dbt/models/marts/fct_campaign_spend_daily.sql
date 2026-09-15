-- marts.fct_campaign_spend_daily - ad spend attributed to CRM campaigns and lines of
-- business, with the leads and revenue it bought. Where CPL, CPA and CER come from.
-- Grain: one row per (entity_id, campaign, line_of_business, day).
--
-- THE ATTRIBUTION RULE, set by Nicolas on 2026-09-10 and applied here literally:
--
--   Cost is split PER LEAD, not per the campaign's nominal line. A campaign that spent
--   $100 on a day and produced 1 Long Distance lead and 2 Local leads gives $33.33 to
--   LD and $66.67 to Local. The share is leads_received / campaign_day_leads_total,
--   both already on fct_campaign_daily, across both instances.
--
-- The shares of one (campaign, day) sum to exactly 1, so attributed spend sums back to
-- the campaign's spend to the cent - tests/assert_ad_spend_reconciles.sql proves it on
-- every build, against raw, including the unmapped remainder.
--
-- A DAY WITH SPEND AND NO LEADS HAS NOTHING TO SPLIT BY. That spend is real and must
-- not vanish, so it lands on line_of_business = 'unassigned' with leads = 0 and
-- has_leads = false. A monthly CPL that ignores those rows understates cost; a consumer
-- who wants "spend per line" sums them into the campaign total. Both are honest;
-- silently dropping them is not.
--
-- COMMERCIAL IS NOT SPECIAL-CASED, same as fct_campaign_daily: `Eco Commercial (Google
-- Ads)` and `Bing Ads Commercial` are read by their campaign row, whole. If a
-- commercial campaign ever produces a residential lead the split still shows it.
--
-- Clicks, impressions and platform conversions are split by the same share, so they
-- can be summed per line without double counting; per campaign they sum to raw.
--
-- Cohort grain: spend_date = the day the LEAD arrived (lead_received_date), which is
-- also the platform's day - both PT. A lead from last week has not matured; open_leads
-- travels on the row like every other cohort mart.

{{ config(materialized='table') }}

with spend as (
    -- Mapped spend only. Unmapped spend is the review queue, mart_unmapped_ad_spend.
    select
        campaign,
        campaign_group,
        spend_date_local                                    as spend_date,
        sum(spend)                                          as spend,
        sum(impressions)                                    as impressions,
        sum(clicks)                                         as clicks,
        sum(platform_conversions)                           as platform_conversions,
        max(synced_at)                                      as spend_synced_at
    from {{ ref('int_ad_spend_daily') }}
    where is_mapped
    group by 1, 2, 3
),

leads as (
    select
        entity_id,
        campaign,
        campaign_group,
        line_of_business,
        lead_received_date,
        channel_group,
        leads_received,
        campaign_day_leads_total,
        valid_leads,
        bad_leads,
        booked_leads,
        lost_leads,
        cancelled_leads,
        open_leads,
        booked_estimated_value,
        invoiced_value,
        invoiced_deals,
        synced_at
    from {{ ref('fct_campaign_daily') }}
),

-- One entity today; the spend rows that have no leads still need one.
entity as (
    select distinct entity_id from {{ ref('dim_instance') }}
),

-- Spend joined onto every line that received leads from that campaign that day.
attributed as (
    select
        l.entity_id,
        l.campaign,
        l.campaign_group,
        l.line_of_business,
        l.lead_received_date                                as spend_date,
        l.channel_group,
        true                                                as has_leads,
        (l.leads_received::numeric / l.campaign_day_leads_total) as spend_share,
        s.spend, s.impressions, s.clicks, s.platform_conversions,
        l.leads_received, l.valid_leads, l.bad_leads, l.booked_leads, l.lost_leads,
        l.cancelled_leads, l.open_leads, l.booked_estimated_value, l.invoiced_value,
        l.invoiced_deals,
        greatest(l.synced_at, s.spend_synced_at)            as synced_at
    from leads l
    join spend s
      on  s.campaign   = l.campaign
      and s.spend_date = l.lead_received_date
),

-- Spend on days with no lead from that campaign: whole, on 'unassigned'.
unattributed as (
    select
        e.entity_id,
        s.campaign,
        s.campaign_group,
        'unassigned'                                        as line_of_business,
        s.spend_date,
        null::text                                          as channel_group,
        false                                               as has_leads,
        1::numeric                                          as spend_share,
        s.spend, s.impressions, s.clicks, s.platform_conversions,
        0 as leads_received, 0 as valid_leads, 0 as bad_leads, 0 as booked_leads,
        0 as lost_leads, 0 as cancelled_leads, 0 as open_leads,
        null::numeric as booked_estimated_value, null::numeric as invoiced_value,
        0 as invoiced_deals,
        s.spend_synced_at                                   as synced_at
    from spend s
    cross join entity e
    where not exists (
        select 1 from leads l
        where l.campaign = s.campaign and l.lead_received_date = s.spend_date
    )
),

unioned as (
    select * from attributed
    union all
    select * from unattributed
)

select
    entity_id || ':' || campaign || ':' || line_of_business
        || ':' || to_char(spend_date, 'YYYYMMDD')            as campaign_spend_day_key,
    entity_id,
    campaign_group,
    campaign,
    line_of_business,
    spend_date,
    channel_group,
    has_leads,
    round(spend_share, 6)                                   as spend_share,

    round(spend * spend_share, 2)                           as spend,
    round(impressions * spend_share, 2)                     as impressions,
    round(clicks * spend_share, 2)                          as clicks,
    round(platform_conversions * spend_share, 2)            as platform_conversions,

    leads_received,
    valid_leads,
    bad_leads,
    booked_leads,
    lost_leads,
    cancelled_leads,
    open_leads,
    booked_estimated_value,
    invoiced_value,
    invoiced_deals,

    -- The KPIs. Null, never zero, when the denominator is empty: a day with spend and
    -- no leads has an undefined CPL, not a free one.
    case when leads_received > 0
         then round(spend * spend_share / leads_received, 2) end   as cost_per_lead,
    case when valid_leads > 0
         then round(spend * spend_share / valid_leads, 2) end      as cost_per_valid_lead,
    case when booked_leads > 0
         then round(spend * spend_share / booked_leads, 2) end     as cost_per_acquisition,
    -- CER: cost-to-revenue, spend per invoiced dollar. 0.10 = ten cents of ads per
    -- dollar billed. Invoiced only, so it is realised revenue, not estimates.
    case when invoiced_value > 0
         then round(spend * spend_share / invoiced_value, 4) end   as cost_efficiency_ratio,

    synced_at
from unioned
