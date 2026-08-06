-- Leads from the daily windowed poll. created_at_utc is already timestamptz (UTC
-- instant). service_date is a YYYYMMDD int (0 = none). status is the lead enum
-- (0=New, 1=In Progress, 30=Lost, 50=Bad Lead - confirmed via lost/bad reasons).
select
    source_instance_id || ':' || id        as lead_key,
    source_instance_id,
    entity_id,
    id                                      as external_lead_id,
    customer_name,
    nullif(phone_number, '')                as customer_phone,
    nullif(email_address, '')               as customer_email,
    nullif(referral_source_name, '')        as referral_source,
    nullif(sales_person, '')                as sales_person,
    nullif(branch_name, '')                 as branch_name,
    nullif(move_size_name, '')              as move_size,
    case when service_date > 0
         then to_date(service_date::text, 'YYYYMMDD') end as service_date,
    nullif(origin_city, '')                 as origin_city,
    nullif(origin_state, '')                as origin_state,
    nullif(origin_zip, '')                  as origin_zip,
    nullif(destination_city, '')            as destination_city,
    nullif(destination_state, '')           as destination_state,
    nullif(destination_zip, '')             as destination_zip,
    status                                  as lead_status_code,
    nullif(lost_reason, '')                 as lost_reason,
    nullif(bad_lead_reason, '')             as bad_lead_reason,
    created_at_utc,
    _sm_extracted_at                        as synced_at
from {{ source('smartmoving', 'leads') }}
