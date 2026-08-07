-- Charge lines per job, estimated and actual in ONE model separated by
-- charge_kind. The two source tables have byte-identical shapes, so a union with a
-- discriminator beats two parallel models everywhere downstream: one set of tests,
-- one join, and "estimated vs actual" becomes a filter rather than a schema choice.
--
-- Grain: (source_instance_id, external_job_id, charge_kind, charge_seq).
-- charge_seq is _dlt_list_idx, which exists and is unique per parent on both
-- tables (verified 1458/1458 and 121/121).
--
-- charge_category is an int enum (observed 1,2,3,4,7,9,10). Deliberately NOT
-- labelled here - inventing names for unverified codes is how wrong business logic
-- gets baked in. It needs a seed, mapped from the SmartMoving UI. See IMPLEMENTATION_STATUS.

with jobs as (
    select job_dlt_id, source_instance_id, entity_id, external_job_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunity_jobs') }}
),

estimated as (
    select 'estimated' as charge_kind, * from {{ source('smartmoving', 'opportunities_enriched__jobs__estimated_charges') }}
),

actual as (
    select 'actual' as charge_kind, * from {{ source('smartmoving', 'opportunities_enriched__jobs__actual_charges') }}
),

unioned as (
    select * from estimated
    union all
    select * from actual
)

select
    j.source_instance_id || ':' || j.external_job_id
        || ':' || u.charge_kind || ':' || u._dlt_list_idx  as charge_key,
    j.source_instance_id,
    j.entity_id,
    j.external_job_id,
    j.external_opportunity_id,
    u.charge_kind,
    u._dlt_list_idx                     as charge_seq,

    nullif(u.name, '')                  as charge_name,
    u.charge_category                   as charge_category_code,
    nullif(u.description, '')           as charge_description,
    nullif(u.editable_description, '')  as charge_editable_description,
    u.sort_order,
    u.subtotal,
    u.discount_amount,
    u.total_cost
from unioned u
join jobs j
  on j.job_dlt_id = u._dlt_parent_id
