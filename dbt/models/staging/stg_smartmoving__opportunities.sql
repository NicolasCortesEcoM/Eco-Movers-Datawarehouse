-- Opportunities nested under the customer sweep. Links to its customer via the
-- dlt parent id. `status` is the platform status INT (4=Booked, 11=Closed
-- confirmed; see smartmoving_api_findings.md) - distinct from the custom
-- leadStatus string, which the sweep does not return.
select
    _dlt_id             as opportunity_dlt_id,
    _dlt_parent_id      as customer_dlt_id,
    id                  as external_opportunity_id,
    nullif(quote_number, '') as quote_number,
    status              as opportunity_status_code
from {{ source('smartmoving', 'customers_service_window__opportunities') }}
