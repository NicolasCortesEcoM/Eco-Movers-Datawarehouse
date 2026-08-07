-- stg_smartmoving__branches - branch reference list per instance.
-- Renamed and typed only. dispatch_location__* carries a real geocoded address
-- (street/city/state/zip/lat/lng), which is the only structured, coordinate-level
-- geography the API gives us for free anywhere.

select
    source_instance_id,
    entity_id,
    id                              as external_branch_id,
    name                            as branch_name,
    phone_number                    as branch_phone,
    is_primary                      as is_primary_branch,
    dispatch_location__full_address as dispatch_address_full,
    dispatch_location__street       as dispatch_street,
    dispatch_location__city         as dispatch_city,
    dispatch_location__state        as dispatch_state,
    dispatch_location__zip          as dispatch_zip,
    dispatch_location__lat          as dispatch_lat,
    dispatch_location__lng          as dispatch_lng,
    _sm_extracted_at                as synced_at
from {{ source('smartmoving', 'dim_branches') }}
