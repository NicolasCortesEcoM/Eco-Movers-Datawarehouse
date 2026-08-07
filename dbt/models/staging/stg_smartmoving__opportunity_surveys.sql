-- Surveys / in-home estimates scheduled against an opportunity.
-- Grain: (source_instance_id, external_opportunity_id, survey_seq).
--
-- start_at_utc is a genuine UTC instant from the API - unlike the scheduled-report
-- columns named "* at Utc", which render in the CRM's configured timezone. Do not
-- treat the two as the same kind of value.

with surveys as (
    select * from {{ source('smartmoving', 'opportunities_enriched__surveys') }}
),

opportunities as (
    select opportunity_dlt_id, source_instance_id, entity_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
)

select
    o.source_instance_id || ':' || o.external_opportunity_id || ':' || s._dlt_list_idx as survey_key,
    o.source_instance_id,
    o.entity_id,
    o.external_opportunity_id,
    s._dlt_list_idx                         as survey_seq,

    s.type                                  as survey_type_code,
    s.start_at_utc,
    s.duration_minutes,
    s.is_confirmed,
    nullif(s.notes, '')                     as survey_notes,
    nullif(s.assigned_to__name, '')         as assigned_to_name,
    nullif(s.assigned_to__mobile_number, '') as assigned_to_mobile,
    nullif(s.assigned_to__branch_id, '')    as assigned_to_branch_id,
    nullif(s.assigned_to__title, '')        as assigned_to_title
from surveys s
join opportunities o
  on o.opportunity_dlt_id = s._dlt_parent_id
