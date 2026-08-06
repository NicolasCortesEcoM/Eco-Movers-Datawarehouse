-- core.leads - canonical leads. Grain: one row per (source_instance_id,
-- external_lead_id). Disposition is derived from the reason fields (reliable)
-- rather than the raw status int. Local time uses the entity timezone
-- (America/Los_Angeles) inline; generalizes to core.branches.timezone when an
-- entity in another zone is onboarded.

{% set entity_tz = "'America/Los_Angeles'" %}

with leads as (
    select * from {{ ref('stg_smartmoving__leads') }}
)

select
    lead_key,
    entity_id,
    source_instance_id,
    external_lead_id,
    customer_name,
    customer_phone,
    customer_email,
    referral_source,
    sales_person,
    branch_name,
    move_size,
    service_date,
    origin_city, origin_state, origin_zip,
    destination_city, destination_state, destination_zip,
    lead_status_code,
    case
        when bad_lead_reason is not null then 'Bad Lead'
        when lost_reason is not null     then 'Lost'
        when lead_status_code = 1        then 'In Progress'
        when lead_status_code = 0        then 'New'
        else 'status_' || lead_status_code
    end                                                     as lead_disposition,
    lost_reason,
    bad_lead_reason,
    created_at_utc,
    (created_at_utc at time zone {{ entity_tz }})           as created_at_local,
    (created_at_utc at time zone {{ entity_tz }})::date     as created_date_local,
    synced_at
from leads
