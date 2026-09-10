-- serving.sales_agent_daily_v1 - PUBLIC CONTRACT (Sales).
--
-- Sales performance per agent, line of business and lead-arrival day. Consumed via
-- app_read, RLS-scoped by entity_id. Additive changes ship freely; breaking changes
-- require v2 with a 90-day overlap.
--
-- THE GRAIN IS A COHORT. A row describes what became of the leads that reached this
-- agent on this day, whenever the outcome landed - a lead received in March and
-- booked in May counts on the March row. That is the only grain a conversion rate is
-- answerable on. "How much did we book in July" is a different question and this is
-- not the table for it.
--
-- ⚠️ TWO THINGS A CONSUMER MUST HONOUR, or the numbers mislead:
--
--   1. RECENT COHORTS ARE NOT COMPARABLE TO OLD ONES. Leads from the last few weeks
--      have not had time to be lost yet, so their conversion looks inflated -
--      August 2026 read 71% against a 45-50% baseline. Either exclude the last ~60
--      days or show `open_leads` beside the rate; a cohort with open leads is still
--      settling.
--   2. `is_within_assignment = false` means the lead landed in a line the agent was
--      not rostered for on that date. It is a data-quality signal, not a filter -
--      but it currently covers 42% of leads because dim_agent_assignment was built
--      for 2026 and the 2023-2025 history falls outside its validity windows.
--      Until that seed is extended, do not slice by it.
--
-- Prior-tenant rows are already excluded upstream (core.opportunities.is_in_scope).

select
    agent_day_key,
    entity_id,
    agent_name,
    is_sales_agent,
    role,
    line_of_business,
    lead_received_date,

    leads_received,
    valid_leads,
    bad_leads,
    booked_leads,
    lost_leads,
    cancelled_leads,
    open_leads,
    conversion_pct,

    -- Cancellations among the deals this cohort WON, over booked + cancelled. A
    -- cancellation replaces the booked status upstream, so adding it back is what
    -- reconstructs "ever booked" - the only honest denominator. Null when nothing was
    -- ever booked. For cancellations counted on the day they happened, and for the
    -- money that walked, use serving.cancellations_daily_v1.
    cancellation_pct,

    -- Leads whose line of business is inferred from the branch because the lead has
    -- not converted to a job yet. Non-zero only on recent cohorts; it is the caveat
    -- to attach to any split by line on the last few days.
    provisional_line_leads,

    invoiced_deals,
    avg_invoiced_deal_size,
    booked_estimated_value,
    invoiced_value,

    lost_to_competitor,
    lost_on_price,
    lost_no_contact,
    lost_to_diy,
    lost_reason_unknown,

    avg_minutes_to_first_contact,
    leads_with_contact_timing,
    is_within_assignment,

    synced_at
from {{ ref('fct_agent_leads_daily') }}
