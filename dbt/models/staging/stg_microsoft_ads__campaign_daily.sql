-- Microsoft Advertising (Bing Ads) cost per campaign per day, typed. Grain
-- (platform, account_id, campaign_id, spend_date_local) - the raw PK, unchanged.
-- Same columns as stg_google_ads__campaign_daily wherever the platforms overlap, so
-- int_ad_spend_daily unions them without renaming.
--
-- MONEY IS CAST HERE and nowhere else (CLAUDE.md "Money"). Microsoft sends `Spend`
-- and `Revenue` as decimal strings; raw keeps the string, this view casts to numeric.
-- `cost_micros` is derived (cost x 1,000,000) only so the column set matches Google's.
--
-- THE DAY IS THE ACCOUNT'S DAY: the report is requested in the account's own time
-- zone (Eco-Movers: Pacific), so `spend_date_local` carries the `_local` suffix and
-- `account_time_zone` travels on the row from the accounts table.
--
-- `campaign_type` ('Search & content', 'Audience', 'Performance max' ...) is the
-- closest thing Microsoft has to Google's advertising_channel_type.

with acct as (
    select account_id, account_time_zone
    from {{ ref('stg_microsoft_ads__accounts') }}
)

select
    c.platform || ':' || c.account_id || ':' || c.campaign_id
        || ':' || to_char(c.date, 'YYYYMMDD')               as campaign_day_key,
    c.platform,
    c.account_id,
    nullif(trim(c.account_name), '')                        as account_name,
    c.account_number,
    c.campaign_id,
    nullif(trim(c.campaign_name), '')                       as campaign_name,
    c.campaign_status,
    c.campaign_type,
    c.date                                                  as spend_date_local,
    a.account_time_zone,
    c.currency,
    c.spend::numeric                                        as cost,
    (c.spend::numeric * 1000000)::bigint                    as cost_micros,
    c.impressions,
    c.clicks,
    c.conversions::numeric                                  as conversions,
    c.conversions_value::numeric                            as conversions_value,
    c.all_conversions::numeric                              as all_conversions,
    c._payload                                              as payload,
    c._extracted_at                                         as extracted_at
from {{ source('microsoft_ads', 'campaign_daily') }} c
left join acct a on a.account_id = c.account_id
