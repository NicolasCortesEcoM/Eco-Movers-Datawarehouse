-- Jobs under an enriched opportunity. Grain: one row per
-- (source_instance_id, external_job_id) - verified unique (765/765).
--
-- Child tables carry no instance stamp (dlt stamps only the root row), so the
-- parent is joined for source_instance_id / entity_id. All 765 rows resolve.
--
-- job_date is a YYYYMMDD int here but an ISO string on the sweep's job table.
-- Either way it is a local business date and is NEVER timezone-converted.

with jobs as (
    select * from {{ source('smartmoving', 'opportunities_enriched__jobs') }}
),

opportunities as (
    select
        opportunity_dlt_id,
        source_instance_id,
        entity_id,
        external_opportunity_id
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
)

select
    o.source_instance_id || ':' || j.id     as job_key,
    o.source_instance_id,
    o.entity_id,
    j.id                                    as external_job_id,
    o.external_opportunity_id,
    j._dlt_id                               as job_dlt_id,
    j._dlt_list_idx                         as job_seq,

    nullif(j.job_number, '')                as job_number,
    case when j.job_date > 0
         then to_date(j.job_date::text, 'YYYYMMDD') end as job_date,
    j.type                                  as service_type_id,
    j.confirmed                             as is_confirmed,
    -- money: cast at the staging boundary like every other monetary column
    j.total_tips::numeric                   as total_tips,

    nullif(j.arrival_window__id, '')            as arrival_window_id,
    nullif(j.arrival_window__description, '')   as arrival_window_description,
    j.arrival_window__start_time                as arrival_window_start_time,
    j.arrival_window__end_time                  as arrival_window_end_time,
    j.arrival_window__is_default                as arrival_window_is_default,

    j.job_time__labor_time__estimated       as labor_time_estimated,
    j.job_time__labor_time__actual          as labor_time_actual,
    j.job_time__travel_time__estimated      as travel_time_estimated,
    j.job_time__travel_time__actual         as travel_time_actual,
    j.job_time__billable_hours              as billable_hours
from jobs j
join opportunities o
  on o.opportunity_dlt_id = j._dlt_parent_id
