-- The Google Ads manager's account tree, typed. One row per account, the manager
-- itself included (level 0, is_manager = true). Small and replaced on every run.
--
-- Exists so a report can print an account NAME next to a campaign row without a
-- second API call, and so "which child accounts are we reading" is a query, not a
-- memory. Zero API quota cost - Google Ads is free; the ledger records it anyway.

select
    platform || ':' || account_id           as account_key,
    platform,
    account_id,
    nullif(trim(account_name), '')          as account_name,
    coalesce(is_manager, false)             as is_manager,
    level                                   as level_under_manager,
    status,
    currency_code,
    time_zone                               as account_time_zone,
    coalesce(is_test_account, false)        as is_test_account,
    manager_id,
    _extracted_at                           as extracted_at
from {{ source('google_ads', 'accounts') }}
