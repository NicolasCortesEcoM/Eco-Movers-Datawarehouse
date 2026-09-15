-- marts.mart_unmapped_ad_spend - platform campaigns whose spend has nowhere to go.
-- Grain: one row per (platform, account_id, platform_campaign_id).
--
-- THE REVIEW QUEUE FOR dim_ad_campaign_map, the same role mart_unmatched_report_rows
-- plays for the reports. Every dollar here is real, extracted, and absent from
-- fct_campaign_spend_daily - not lost, not guessed, waiting for one CSV row. Sorted by
-- money so the row that matters most is first; `days_since_last_spend` says whether it
-- is a live campaign or history.
--
-- A campaign leaves this table the moment a row for its ID lands in the seed; the
-- reconciliation test guarantees the two tables always sum to raw.

select
    platform || ':' || account_id || ':' || platform_campaign_id  as unmapped_key,
    platform,
    account_id,
    account_name,
    platform_campaign_id,
    platform_campaign_name,
    min(campaign_status)                     as campaign_status,
    min(advertising_channel_type)            as advertising_channel_type,
    min(spend_date_local)                    as first_spend_date,
    max(spend_date_local)                    as last_spend_date,
    (current_date - max(spend_date_local))   as days_since_last_spend,
    count(*)                                 as days_with_spend,
    sum(spend)                               as unmapped_spend,
    sum(clicks)                              as clicks,
    sum(platform_conversions)                as platform_conversions,
    max(synced_at)                           as synced_at
from {{ ref('int_ad_spend_daily') }}
where not is_mapped
group by 1, 2, 3, 4, 5, 6
order by unmapped_spend desc
