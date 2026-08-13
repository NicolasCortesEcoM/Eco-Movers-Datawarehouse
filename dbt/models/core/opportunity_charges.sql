-- core.opportunity_charges - charge lines, estimated and actual.
-- Grain: (source_instance_id, external_job_id, charge_kind, charge_seq).
--
-- No observation layer here, deliberately. Charge lines only ever come from one
-- source (the opportunity detail call), and dlt replaces a parent's child rows
-- wholesale on merge - so exactly one generation exists at any time and there is
-- nothing to reconcile. Adding pick_latest machinery would be cost with no benefit.
--
-- charge_category_code is the raw int enum (observed 1,2,3,4,7,9,10). Left
-- unlabelled until the mapping is read off the SmartMoving UI - inventing names
-- for unverified codes is how wrong business logic gets baked in.

select
    c.charge_key,
    c.entity_id,
    c.source_instance_id,
    c.external_job_id,
    c.external_opportunity_id,
    c.charge_kind,
    c.charge_seq,
    c.charge_name,
    c.charge_category_code,
    c.charge_description,
    c.sort_order,
    -- already numeric: staging casts money at the boundary, so nothing here
    -- re-types it. See stg_smartmoving__opportunity_job_charges.
    c.subtotal,
    c.discount_amount,
    c.total_cost,
    o.synced_at
from {{ ref('stg_smartmoving__opportunity_job_charges') }} c
left join {{ ref('opportunities') }} o
       on o.source_instance_id = c.source_instance_id
      and o.external_opportunity_id = c.external_opportunity_id
