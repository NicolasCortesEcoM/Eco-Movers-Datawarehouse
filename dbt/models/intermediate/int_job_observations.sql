-- Every OBSERVATION any source has made about a job.
-- Grain: (job_key, source, observed_at). Same shape and rules as
-- int_opportunity_observations: wide, nullable, nothing resolved here.
--
-- Two API sources see jobs today and they overlap completely (765/765 job ids
-- shared), but they carry different depth: the sweep has number/date/type, the
-- enrichment adds arrival window, crew time and tips.
--
-- The Phase 5 report_all_jobs arm lands here - it is what brings structured
-- origin/destination, actual costs and lifecycle timestamps, none of which any
-- API source provides.

with enrichment as (
    select
        j.job_key,
        j.entity_id,
        j.source_instance_id,
        j.external_job_id,
        j.external_opportunity_id,
        'api_enrichment'            as source,
        1                           as source_priority,
        o.observed_at,

        j.job_number,
        j.job_date                  as service_date,
        j.service_type_id,
        j.is_confirmed,
        j.total_tips::numeric       as total_tips,
        j.arrival_window_description,
        j.labor_time_estimated,
        j.labor_time_actual,
        j.travel_time_estimated,
        j.travel_time_actual,
        j.billable_hours
    from {{ ref('stg_smartmoving__opportunity_jobs') }} j
    join {{ ref('stg_smartmoving__opportunities_enriched') }} o
      on o.source_instance_id = j.source_instance_id
     and o.external_opportunity_id = j.external_opportunity_id
),

sweep as (
    select
        c.source_instance_id || ':' || j.external_job_id as job_key,
        c.entity_id,
        c.source_instance_id,
        j.external_job_id,
        o.external_opportunity_id,
        'api_sweep'                 as source,
        2                           as source_priority,
        c.synced_at                 as observed_at,

        j.job_number,
        j.service_date,
        j.service_type_id,
        null::boolean               as is_confirmed,
        null::numeric               as total_tips,
        null::text                  as arrival_window_description,
        null::bigint, null::bigint, null::bigint, null::bigint, null::bigint
    from {{ ref('stg_smartmoving__jobs') }} j
    join {{ ref('stg_smartmoving__opportunities') }} o
      on o.opportunity_dlt_id = j.opportunity_dlt_id
    join {{ ref('stg_smartmoving__customers') }} c
      on c.customer_dlt_id = j.customer_dlt_id
),

-- The All Jobs report, contributing ONLY the fields it shares with an API source.
--
-- Its ~60 exclusive fields - structured addresses, actual costs, lifecycle
-- timestamps - are NOT here on purpose. No other source reports them, so there is no
-- disagreement for pick_latest to resolve, and carrying them through this union
-- would mean ~60 nullable columns in every other arm to resolve a conflict that
-- cannot occur. They join into core.jobs directly from int_report_all_jobs_latest.
--
-- external_opportunity_id is null here: the report identifies the opportunity by
-- quote number, not GUID, and inventing a join to fill it in would put a guess into
-- the observation layer. core.jobs already gets that link from the API arms.
report_all_jobs as (
    select
        job_key,
        entity_id,
        source_instance_id,
        external_job_id,
        null::text                  as external_opportunity_id,
        'report_all_jobs'           as source,
        4                           as source_priority,
        observed_at,

        job_number,
        service_date_local          as service_date,
        null::bigint                as service_type_id,
        null::boolean               as is_confirmed,
        null::numeric               as total_tips,
        null::text                  as arrival_window_description,
        null::bigint, null::bigint, null::bigint, null::bigint, null::bigint
    from {{ ref('int_report_all_jobs_latest') }}
)

select * from enrichment
union all select * from sweep
union all select * from report_all_jobs
