-- Crew member names per job (flat strings, no ids).
-- Grain: (source_instance_id, external_job_id, crew_seq).

with crew as (
    select * from {{ source('smartmoving', 'opportunities_enriched__jobs__crew_members') }}
),

jobs as (
    select job_dlt_id, source_instance_id, entity_id, external_job_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunity_jobs') }}
)

select
    j.source_instance_id || ':' || j.external_job_id || ':' || c._dlt_list_idx as crew_key,
    j.source_instance_id,
    j.entity_id,
    j.external_job_id,
    j.external_opportunity_id,
    c._dlt_list_idx             as crew_seq,
    nullif(trim(c.value), '')   as crew_member_name
from crew c
join jobs j
  on j.job_dlt_id = c._dlt_parent_id
