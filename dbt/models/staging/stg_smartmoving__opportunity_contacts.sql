-- Additional named contacts on an opportunity, beyond the primary customer.
-- Grain: (source_instance_id, external_opportunity_id, contact_seq).
--
-- Not available from ANY list endpoint - the per-opportunity detail call is the
-- only source. Low volume today (18 rows) but it is real contact data the leads
-- feed cannot provide.

with contacts as (
    select * from {{ source('smartmoving', 'opportunities_enriched__contacts') }}
),

opportunities as (
    select opportunity_dlt_id, source_instance_id, entity_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
)

select
    o.source_instance_id || ':' || o.external_opportunity_id || ':' || c._dlt_list_idx as contact_key,
    o.source_instance_id,
    o.entity_id,
    o.external_opportunity_id,
    c._dlt_list_idx                 as contact_seq,

    nullif(trim(c.name), '')        as contact_name,
    nullif(c.email_address, '')     as contact_email,
    nullif(c.phone_number, '')      as contact_phone,
    c.phone_type                    as contact_phone_type_code
from contacts c
join opportunities o
  on o.opportunity_dlt_id = c._dlt_parent_id
