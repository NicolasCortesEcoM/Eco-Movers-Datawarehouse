-- marts.int_ad_spend_daily - every ad platform's spend, one row per platform campaign
-- per day, with the CRM source it maps to (or null).
-- Grain: (platform, account_id, platform_campaign_id, spend_date_local).
--
-- THE ONE PLACE PLATFORM SPEND IS UNIONED AND MAPPED. Both marts downstream -
-- fct_campaign_spend_daily (attributed) and mart_unmapped_ad_spend (the review queue) -
-- read this, so "mapped" and "unmapped" are complements of one row set by
-- construction, and their sum always equals raw. A platform is added here once, as
-- one more union arm reading its stg_<platform>__campaign_daily.
--
-- MAPPING IS BY ID, NOT NAME, and bounded by validity dates: a platform campaign can
-- be re-pointed at a different CRM source without losing its history. The CRM label
-- (`campaign`) is derived with the SAME rule fct_campaign_daily uses -
-- coalesce(source_clean, raw) - so the two tables join exactly. Getting that from
-- dim_referral_source here, rather than storing it in the map, means the map holds
-- one fact (which CRM source) and cannot drift from the seed that owns the labels.

with google as (
    select
        platform,
        account_id,
        account_name,
        campaign_id                          as platform_campaign_id,
        campaign_name                        as platform_campaign_name,
        campaign_status,
        advertising_channel_type,
        spend_date_local,
        currency,
        cost                                 as spend,
        impressions,
        clicks,
        conversions                          as platform_conversions,
        extracted_at
    from {{ ref('stg_google_ads__campaign_daily') }}
),

-- Future arms: meta_ads, bing_ads. Same columns, same grain.
spend as (
    select * from google
),

map as (
    select
        platform,
        account_id,
        platform_campaign_id,
        {{ norm_text('crm_referral_source') }}   as referral_key,
        crm_referral_source,
        valid_from,
        valid_to
    from {{ ref('dim_ad_campaign_map') }}
),

-- Same key and same label rule as core.opportunities' referral CTE.
referral as (
    select distinct on ({{ norm_text('referral_source_raw') }})
        {{ norm_text('referral_source_raw') }}   as referral_key,
        coalesce(nullif(trim(source_clean), ''), trim(referral_source_raw)) as campaign,
        nullif(trim(campaign_group), '')         as campaign_group
    from {{ ref('dim_referral_source') }}
    order by 1, referral_source_raw
)

select
    s.platform || ':' || s.account_id || ':' || s.platform_campaign_id
        || ':' || to_char(s.spend_date_local, 'YYYYMMDD')     as spend_key,
    s.platform,
    s.account_id,
    s.account_name,
    s.platform_campaign_id,
    s.platform_campaign_name,
    s.campaign_status,
    s.advertising_channel_type,
    s.spend_date_local,
    s.currency,
    s.spend,
    s.impressions,
    s.clicks,
    s.platform_conversions,

    m.crm_referral_source,
    r.campaign,
    r.campaign_group,
    (m.platform_campaign_id is not null)                       as is_mapped,
    s.extracted_at                                             as synced_at
from spend s
left join map m
       on  m.platform             = s.platform
       and m.account_id           = s.account_id
       and m.platform_campaign_id = s.platform_campaign_id
       and s.spend_date_local between m.valid_from and m.valid_to
left join referral r
       on r.referral_key = m.referral_key
