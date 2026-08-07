-- The newest observation each source has made about each opportunity.
--
-- Grain: (opportunity_key, source). Collapses the observation history to one row
-- per source, so core.opportunities joins a handful of narrow CTEs instead of
-- scanning the full history once per field.
--
-- Materialized as a table on purpose: it is the fan-in point every field in
-- core.opportunities reads through.

{{ config(materialized='table') }}

select distinct on (opportunity_key, source)
    *
from {{ ref('int_opportunity_observations') }}
order by opportunity_key, source, observed_at desc, source_priority
