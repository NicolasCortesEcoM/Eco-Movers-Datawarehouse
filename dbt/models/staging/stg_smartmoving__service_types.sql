-- Service-type reference per instance. Business key is (source_instance_id, id)
-- because the small integer ids are only unique within an instance.
select
    source_instance_id,
    entity_id,
    id          as service_type_id,
    name        as service_type_name
from {{ source('smartmoving', 'dim_service_types') }}
