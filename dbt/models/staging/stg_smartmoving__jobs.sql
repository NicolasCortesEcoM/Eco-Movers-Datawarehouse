-- Jobs nested under each opportunity in the sweep. service_date arrives as an
-- ISO string ("2026-07-20") here (unlike the YYYYMMDD int elsewhere) - it is a
-- local business date and is NEVER timezone-converted. type -> service_type_id.
select
    _dlt_id                             as job_dlt_id,
    _dlt_parent_id                      as opportunity_dlt_id,
    _dlt_root_id                        as customer_dlt_id,
    id                                  as external_job_id,
    nullif(job_number, '')              as job_number,
    nullif(service_date, '')::date      as service_date,
    type                                as service_type_id
from {{ source('smartmoving', 'customers_service_window__opportunities__jobs') }}
