-- Google Ads cost per campaign per day, typed. Grain (platform, account_id,
-- campaign_id, spend_date_local) - the raw PK, unchanged.
--
-- MONEY IS CAST HERE and nowhere else (CLAUDE.md "Money"). Google sends cost in
-- micros - cost x 1,000,000, as an integer, precisely so no float is ever involved.
-- Dividing by 1e6 in numeric keeps it exact; dividing in double precision would not.
--
-- THE DAY IS THE ACCOUNT'S DAY. `segments.date` is the calendar day in the account's
-- own time zone, which is the only day Google reports by. It is exposed as
-- `spend_date_local`, the `_local` suffix the repo uses for anything not in UTC, and
-- `account_time_zone` travels on the row so a join to a UTC-dated table can convert
-- deliberately instead of by accident.
--
-- ACCOUNT_ID IS PART OF THE KEY on purpose: it is the CHILD customer id the row was
-- read from under the manager. Two accounts with the same campaign id can never
-- collide, and every row says which account it came from. That is what the
-- campaign map (dim_ad_campaign_map) joins on: (platform, account_id, campaign_id),
-- never the campaign name, which gets renamed.
--
-- Google restates the last 2-3 days of cost and up to 30 days of conversions; raw is
-- re-read over an overlapping window and merged, so this view always shows the
-- latest restatement. All rows kept; nothing to dedupe.

select
    platform || ':' || account_id || ':' || campaign_id
        || ':' || to_char(date, 'YYYYMMDD')                 as campaign_day_key,
    platform,
    account_id,
    nullif(trim(account_name), '')                          as account_name,
    campaign_id,
    nullif(trim(campaign_name), '')                         as campaign_name,
    campaign_status,
    advertising_channel_type,
    advertising_channel_sub_type,
    bidding_strategy_type,
    date                                                    as spend_date_local,
    account_time_zone,
    currency,
    (cost_micros::numeric / 1000000)                        as cost,
    cost_micros,
    impressions,
    clicks,
    conversions::numeric                                    as conversions,
    conversions_value::numeric                              as conversions_value,
    all_conversions::numeric                                as all_conversions,
    _payload                                                as payload,
    _extracted_at                                           as extracted_at
from {{ source('google_ads', 'campaign_daily') }}
