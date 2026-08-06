-- Customers from the service-date sweep. Carries the dlt row id so children
-- (opportunities, jobs) can link back to source_instance_id / entity_id.
select
    _dlt_id                     as customer_dlt_id,
    source_instance_id,
    entity_id,
    id                          as external_customer_id,
    name                        as customer_name,
    nullif(phone_number, '')    as customer_phone,
    nullif(email_address, '')   as customer_email,
    nullif(address, '')         as customer_address,
    _sm_extracted_at            as synced_at
from {{ source('smartmoving', 'customers_service_window') }}
