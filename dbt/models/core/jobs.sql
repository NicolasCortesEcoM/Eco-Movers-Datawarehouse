-- core.jobs - canonical upcoming-jobs entity, resolved across the sweep's
-- customer -> opportunity -> job hierarchy, with service type resolved.
-- Grain: one row per (source_instance_id, external_job_id).
-- Business keys are always (entity_id/instance, external_id) - never a naked id.
-- Branch, origin/destination and rich fields are NOT in the sweep; they arrive
-- later via opportunity enrichment and will be additive columns here.

with jobs as (
    select * from {{ ref('stg_smartmoving__jobs') }}
),
opportunities as (
    select * from {{ ref('stg_smartmoving__opportunities') }}
),
customers as (
    select * from {{ ref('stg_smartmoving__customers') }}
),
service_types as (
    select * from {{ ref('stg_smartmoving__service_types') }}
)

select
    c.source_instance_id || ':' || j.external_job_id as job_key,
    c.entity_id,
    c.source_instance_id,
    j.external_job_id,
    j.job_number,
    o.external_opportunity_id,
    o.quote_number,
    o.opportunity_status_code,
    case o.opportunity_status_code
        when 4  then 'Booked'
        when 11 then 'Closed'
        else 'status_' || o.opportunity_status_code
    end                                             as opportunity_status_label,
    j.service_date,
    j.service_type_id,
    st.service_type_name,
    c.external_customer_id,
    c.customer_name,
    c.customer_phone,
    c.customer_email,
    c.customer_address,
    c.synced_at
from jobs j
join opportunities o
    on o.opportunity_dlt_id = j.opportunity_dlt_id
join customers c
    on c.customer_dlt_id = j.customer_dlt_id
left join service_types st
    on st.source_instance_id = c.source_instance_id
   and st.service_type_id   = j.service_type_id
