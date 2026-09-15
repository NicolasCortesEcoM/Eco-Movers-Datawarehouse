-- Attributed + unmapped = raw, to the cent. The per-lead split must never create or
-- lose money: shares of one (campaign, day) sum to 1, the unmapped queue holds the
-- rest, and a platform arm added to int_ad_spend_daily must not double-load.
--
-- Tolerance is one cent per attributed row: fct_campaign_spend_daily rounds each
-- line's share to 2 decimals, so a campaign-day split three ways can miss the raw
-- figure by up to $0.03 while being exactly right in substance.
with raw_total as (
    select sum(cost) as amount from {{ ref('stg_google_ads__campaign_daily') }}
),
attributed as (
    select sum(spend) as amount, count(*) as n from {{ ref('fct_campaign_spend_daily') }}
),
unmapped as (
    select coalesce(sum(unmapped_spend), 0) as amount from {{ ref('mart_unmapped_ad_spend') }}
)
select r.amount as raw_amount, a.amount as attributed, u.amount as unmapped,
       r.amount - a.amount - u.amount as gap
from raw_total r, attributed a, unmapped u
where abs(r.amount - coalesce(a.amount, 0) - u.amount) > 0.01 * greatest(a.n, 1)
