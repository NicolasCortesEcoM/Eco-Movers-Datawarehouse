-- core.lines_of_business - the line of business of every JOB.
-- Grain: one row per (source_instance_id, external_job_id).
--
-- Three lines: `local`, `long_distance`, `commercial`.
--
-- THE RULE HIERARCHY, in strict order. The first rule that matches wins:
--
--   1. SERVICE TYPE SAYS COMMERCIAL -> commercial. Always. No exception.
--   2. BRANCH -> whatever dim_lob_branch.csv maps it to.
--   3. THE INSTANCE'S OWN LINE, from dim_instance.lob_hint. The `ld` instance IS the
--      long-distance business, so a job there with no mapped branch is long distance,
--      not local. Skipping this step put 114 `ld` jobs under `local`.
--   4. Nothing matched -> `local`, flagged as a fallback so it can be found.
--
-- Why service type outranks everything: it is a property of the WORK, decided when
-- the job is created. Branch is a property of who happened to enter it, and this
-- repository already records that branch_name is unreliable - agents book local jobs
-- against interstate branches. A commercial move booked from a residential branch is
-- still commercial.
--
-- Why the branch mapping is a SEED and not hardcoded: another company on this
-- platform will draw the local/long-distance line differently - by branch, by
-- distance, by their own naming. Editing a CSV must be enough; changing SQL must not
-- be required. The same reasoning as dim_agent_assignment.
--
-- Deliberately NOT used to decide the line: the assigned salesperson. A commercial
-- rep taking a residential move does not make that move commercial, and letting the
-- person decide the work's category makes agent performance depend on itself.

with jobs as (
    select
        source_instance_id,
        external_job_id,
        entity_id,
        job_key,
        branch_name,
        job_type_name,
        service_type_name,
        external_opportunity_id,
        service_date
    from {{ ref('jobs') }}
),

branch_map as (
    select source_instance_id, branch_name, line_of_business
    from {{ ref('dim_lob_branch') }}
),

-- `local_commercial` is a mixed instance, so it gives no usable default - only a
-- single-line instance can stand in for a missing branch.
instance_lob as (
    select instance_id,
           case when lob_hint in ('local', 'long_distance', 'commercial')
                then lob_hint end as lob_hint
    from {{ ref('dim_instance') }}
),

classified as (
    select
        j.*,

        -- Rule 1. Both the job type (All Jobs report) and the service type (API)
        -- are checked: whichever says commercial is enough.
        case
            when {{ norm_text('j.job_type_name') }} like '%commercial%'
              or {{ norm_text('j.service_type_name') }} like '%commercial%'
                then 'commercial'
            -- Rule 2.
            when b.line_of_business is not null then b.line_of_business
            -- Rule 3.
            when il.lob_hint is not null then il.lob_hint
            -- Rule 4.
            else 'local'
        end as line_of_business,

        case
            when {{ norm_text('j.job_type_name') }} like '%commercial%'
              or {{ norm_text('j.service_type_name') }} like '%commercial%'
                then 'service_type'
            when b.line_of_business is not null then 'branch'
            when il.lob_hint is not null then 'instance'
            else 'fallback_default'
        end as lob_source

    from jobs j
    left join branch_map b
      on  b.source_instance_id = j.source_instance_id
      and {{ norm_text('b.branch_name') }} = {{ norm_text('j.branch_name') }}
    left join instance_lob il on il.instance_id = j.source_instance_id
)

select
    job_key,
    source_instance_id,
    entity_id,
    external_job_id,
    external_opportunity_id,
    service_date,
    branch_name,
    job_type_name,
    service_type_name,
    line_of_business,
    lob_source,
    -- An unmapped branch is a data-quality signal, not a silent default. When a new
    -- branch is opened this is what surfaces it: the rows keep flowing as `local`,
    -- and this flag says the classification was a guess.
    (lob_source = 'fallback_default') as is_unclassified
from classified
