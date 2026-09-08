-- dim_status_map must stay unique AFTER norm_text, not just before it.
--
-- core.opportunities joins this seed on {{ norm_text('status_raw') }}, because the
-- report's casing and punctuation drift. norm_text collapses every run of
-- non-alphanumerics to one space, so two rows that look distinct in the CSV -
-- "Lost - price too high" and "Lost price too high" - become the SAME key.
--
-- The seed's own `unique` test is on the raw string and would not notice. The join
-- would then fan out and silently duplicate opportunity rows, inflating every count
-- built on them. 46 rows normalise to 46 distinct keys as of 2026-09-08; this keeps
-- it that way.

select
    {{ norm_text('status_raw') }} as normalised_key,
    count(*)                     as n
from {{ ref('dim_status_map') }}
group by 1
having count(*) > 1
