-- One mapping per (platform, account, campaign id, valid_from). Two rows for the same
-- campaign with overlapping validity would double-count its spend, so the grain is
-- enforced here rather than trusted.
select platform, account_id, platform_campaign_id, valid_from, count(*)
from {{ ref('dim_ad_campaign_map') }}
group by 1, 2, 3, 4
having count(*) > 1
