-- The line of business of an OPPORTUNITY.
--
-- Grain: one row per (source_instance_id, external_opportunity_id) - EVERY opportunity
-- in core, not only the ones that have a job.
--
-- WHY THIS MODEL EXISTS AT ALL. core.lines_of_business classifies JOBS, because the
-- line is a property of the work: what was moved, from where to where. An opportunity
-- is a request for work, and SmartMoving does not create the job until the lead
-- converts. So for the first days of a lead's life there is nothing at job grain to
-- read, and a mart keyed on the line had no answer for it.
--
-- That is what produced `unassigned` on the agent dashboard. It was never a mapping
-- gap - it was the CRM's own sequence showing through: 11.5% of leads under a week old
-- had no line, and 0.0% of everything older than eight days, because by then they have
-- either converted (job exists) or been lost.
--
-- THE FIX IS NOT A DEFAULT PER INSTANCE. `ld` would be safe - it is a single-line
-- business - but `local` is Local AND Commercial, so an instance default there is a
-- coin flip dressed up as a fact. Instead this model applies THE SAME rule hierarchy
-- as core.lines_of_business, one grain up, using the branch the opportunity itself
-- carries:
--
--   1. The opportunity HAS jobs -> take their line. Nothing beats observed work.
--   2. No jobs -> the opportunity's own branch, via dim_lob_branch. Measured
--      2026-09-09: all 30 in-scope job-less opportunities carry a branch and all 30
--      map. This resolves the whole of what used to read `unassigned`.
--   3. No mapped branch -> the instance's own line, from dim_instance.lob_hint. Only
--      helps `ld`; `local_commercial` is deliberately not a line and yields nothing.
--   4. Nothing at all -> `unassigned`, and it stays visible. These are opportunities
--      with no job AND no branch: 824 rows, essentially all of them out of scope or
--      without a lead date, so they never reach the sales marts. Inventing a line for
--      them would be the one thing worse than admitting we do not know.
--
-- Rule 2 CANNOT return `commercial`, because commercial is decided by service type and
-- that lives on the job. A job-less commercial move in the `local` instance therefore
-- reads `local` until its job appears, then corrects itself. Commercial is 1.3% of
-- local-instance jobs, so the exposure is a fraction of a row at any moment - and
-- lob_source says which rows are provisional, so it is measurable rather than assumed.
--
-- `min` on rule 1 is not a judgement about which line is right. It is deterministic,
-- so the grain of everything downstream stays stable across builds, and
-- has_mixed_lines carries the fact that a choice was made rather than hiding it. Five
-- opportunities out of 15,028 span two lines; that does not justify a rule anyone has
-- to remember.
--
-- Extracted here because three marts need it - fct_agent_leads_daily,
-- fct_lead_source_daily and fct_pipeline_current. This repo has already deleted one
-- model (dim_lob_map) for being a second copy of a decision that lived somewhere else.

with opps as (
    select
        source_instance_id,
        external_opportunity_id,
        branch_name
    from {{ ref('opportunities') }}
),

-- Rule 1. Collapsed from job grain.
--
-- 56 jobs carry no opportunity link - real jobs with real job numbers that arrived via
-- the All Jobs report while the opportunity they belong to did not. They are not
-- dropped from the warehouse; core.jobs and core.lines_of_business both keep them.
-- They are dropped HERE because this model exists to be looked up BY opportunity, and
-- a null key groups all 56 into one meaningless row that can never join to anything.
job_line as (
    select
        source_instance_id,
        external_opportunity_id,
        min(line_of_business)                as line_of_business,
        count(distinct line_of_business) > 1 as has_mixed_lines
    from {{ ref('lines_of_business') }}
    where external_opportunity_id is not null
    group by 1, 2
),

-- Rule 2. The same seed core.lines_of_business reads, joined the same way, so branch
-- classification has exactly one definition in this project.
branch_map as (
    select source_instance_id, branch_name, line_of_business
    from {{ ref('dim_lob_branch') }}
),

-- Rule 3. `local_commercial` is a mixed instance and gives no usable default - only a
-- single-line instance can stand in for a missing branch.
instance_lob as (
    select instance_id,
           case when lob_hint in ('local', 'long_distance', 'commercial')
                then lob_hint end as lob_hint
    from {{ ref('dim_instance') }}
)

select
    o.source_instance_id,
    o.external_opportunity_id,

    coalesce(
        j.line_of_business,
        b.line_of_business,
        il.lob_hint,
        'unassigned'
    )                                            as line_of_business,

    coalesce(j.has_mixed_lines, false)           as has_mixed_lines,

    -- Which rule answered. `job` is observed; everything below it is an inference that
    -- will be replaced by `job` as soon as the opportunity converts.
    case
        when j.line_of_business is not null then 'job'
        when b.line_of_business is not null then 'opportunity_branch'
        when il.lob_hint        is not null then 'instance'
        else 'unassigned'
    end                                          as lob_source,

    -- True while the line is a pre-conversion inference. Any report comparing lines to
    -- each other should be able to see how much of a bucket is not yet settled.
    (j.line_of_business is null)                 as is_provisional_line

from opps o
left join job_line j
       on  j.source_instance_id      = o.source_instance_id
       and j.external_opportunity_id = o.external_opportunity_id
left join branch_map b
       on  b.source_instance_id = o.source_instance_id
       and {{ norm_text('b.branch_name') }} = {{ norm_text('o.branch_name') }}
left join instance_lob il
       on il.instance_id = o.source_instance_id
