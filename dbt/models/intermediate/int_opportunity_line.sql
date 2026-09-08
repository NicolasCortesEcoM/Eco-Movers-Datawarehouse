-- The line of business of an OPPORTUNITY, collapsed from its jobs.
--
-- core.lines_of_business is at job grain, and an opportunity can in principle have
-- jobs on more than one line. Five do, out of 15,028 - so this is not a modelling
-- problem, it is a tie-break.
--
-- `min` is not a judgement about which line is right. It is deterministic, so the
-- grain of everything downstream stays stable across builds, and `has_mixed_lines`
-- carries the fact that a choice was made rather than hiding it. Five rows do not
-- justify a rule anyone has to remember.
--
-- Extracted here because two marts need it - fct_agent_leads_daily and
-- fct_lead_source_daily. This repo has already deleted one model (dim_lob_map) for
-- being a second copy of a decision that lived somewhere else; eight lines of SQL is
-- cheap enough to copy and exactly expensive enough to regret.

select
    source_instance_id,
    external_opportunity_id,
    min(line_of_business)                as line_of_business,
    count(distinct line_of_business) > 1 as has_mixed_lines
from {{ ref('lines_of_business') }}
-- 56 jobs carry no opportunity link - real jobs with real job numbers that arrived
-- via the All Jobs report while the opportunity they belong to did not. They are not
-- dropped from the warehouse; core.jobs and core.lines_of_business both keep them.
-- They are dropped HERE because this model exists to be looked up BY opportunity, and
-- a null key groups all 56 into one meaningless row that can never join to anything.
where external_opportunity_id is not null
group by 1, 2
