-- Where two dim_referral_source rows collapse to the same norm_text key, they must
-- agree on every attribute core.opportunities reads from them.
--
-- The seed deliberately carries several raw spellings of one source so that each CRM
-- value resolves - "FMC Yesler Towers" and "FMC- Yesler Towers", "Affiliate - Adam
-- Dankowski SPS" with one space and with two. norm_text collapses them, so the join
-- in core.opportunities deduplicates with `distinct on` and keeps an arbitrary row.
--
-- That is lossless only while the colliding rows say the same thing. Today they do
-- (both pairs are is_paid=FALSE, campaign Affiliate, everything else blank). If a
-- future edit gives one spelling a channel_group and the other none, `distinct on`
-- would silently pick one and the answer would depend on sort order. This fails
-- instead.
--
-- is_paid is a real boolean here: dbt's seed type inference converts the CSV's
-- TRUE/FALSE on load, so it is cast to text for the distinct count rather than
-- trimmed. The first draft called trim() on it and the test errored out.

select
    {{ norm_text('referral_source_raw') }} as normalised_key,
    count(*)                                  as n_rows,
    count(distinct coalesce(nullif(trim(source_clean),  ''), '~')) as n_source_clean,
    count(distinct coalesce(nullif(trim(channel_group), ''), '~')) as n_channel_group,
    count(distinct coalesce(nullif(trim(platform),      ''), '~')) as n_platform,
    count(distinct coalesce(is_paid::text, '~'))                   as n_is_paid
from {{ ref('dim_referral_source') }}
group by 1
having count(*) > 1
   and (count(distinct coalesce(nullif(trim(source_clean),  ''), '~')) > 1
     or count(distinct coalesce(nullif(trim(channel_group), ''), '~')) > 1
     or count(distinct coalesce(nullif(trim(platform),      ''), '~')) > 1
     or count(distinct coalesce(is_paid::text, '~')) > 1)
