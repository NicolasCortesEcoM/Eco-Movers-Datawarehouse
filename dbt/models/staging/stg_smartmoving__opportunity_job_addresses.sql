-- Job addresses as the API returns them: a flat array of STRINGS per job, with no
-- role, no components and no coordinates.
--
-- Grain: (source_instance_id, external_job_id, address_seq), address_seq = _dlt_list_idx.
--
-- DO NOT infer origin/destination from the ordinal. Measured distribution: 84 jobs
-- have 1 address, 645 have 2, 29 have 3, 2 have 4 - so "last one is the
-- destination" is wrong for 115 jobs, and single-address jobs have no destination
-- at all. is_first_address is exposed because position 0 is consistently the
-- origin; nothing beyond that is claimed.
--
-- Structured origin/destination (unit, street, city, state, zip, type) comes from
-- the All Jobs report at zero API cost. The only API route to coordinates is a
-- Premium per-JOB call, deliberately not taken.

with addresses as (
    select * from {{ source('smartmoving', 'opportunities_enriched__jobs__job_addresses') }}
),

jobs as (
    select job_dlt_id, source_instance_id, entity_id, external_job_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunity_jobs') }}
)

select
    j.source_instance_id || ':' || j.external_job_id || ':' || a._dlt_list_idx as address_key,
    j.source_instance_id,
    j.entity_id,
    j.external_job_id,
    j.external_opportunity_id,
    a._dlt_list_idx                     as address_seq,
    (a._dlt_list_idx = 0)               as is_first_address,
    nullif(trim(a.value), '')           as address_full,
    count(*) over (partition by a._dlt_parent_id) as addresses_on_job
from addresses a
join jobs j
  on j.job_dlt_id = a._dlt_parent_id
