-- The Microsoft Advertising ad accounts the authorised user can see, typed. One row
-- per account, replaced on every run. Same purpose as stg_google_ads__accounts: a
-- name next to an account id without another API call.

select
    platform || ':' || account_id           as account_key,
    platform,
    account_id,
    account_number,
    nullif(trim(account_name), '')          as account_name,
    status,
    currency_code,
    time_zone                               as account_time_zone,
    customer_id,
    _extracted_at                           as extracted_at
from {{ source('microsoft_ads', 'accounts') }}
