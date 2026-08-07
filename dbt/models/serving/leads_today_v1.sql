-- serving.leads_today_v1 - PUBLIC CONTRACT (Sales).
-- Leads received today, one row per lead. Consumed via app_read (RLS-scoped by
-- entity_id). Additive changes ship freely; breaking changes require v2 + 90-day
-- overlap.
--
-- "Today" is evaluated per row in that lead's own branch timezone (core.branches,
-- carried through core.leads), not in one hardcoded zone - so a company spanning
-- zones gets the right day on every row.

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
    origin_city,
    origin_state,
    origin_zip,
    destination_city,
    destination_state,
    destination_zip,
    lead_disposition,
    lost_reason,
    bad_lead_reason,
    created_at_utc,
    created_at_local,
    synced_at
from {{ ref('leads') }}
where created_date_local = {{ entity_today('timezone') }}
