-- Newest observation per (job, source). See int_opportunity_latest_by_source.

{{ config(materialized='table') }}

select distinct on (job_key, source)
    *
from {{ ref('int_job_observations') }}
order by job_key, source, observed_at desc, source_priority
