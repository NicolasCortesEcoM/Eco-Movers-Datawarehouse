-- serving.opportunities_v1 - PUBLIC CONTRACT (the general one).
--
-- One row per opportunity, with its identity, its outcome, its dates, its money and
-- its attribution. The contract this project declared its first priority and shipped
-- last, because every column here had to be settled first: the line of business
-- (needs jobs), the agent (needs the roster), the campaign (needs the seed), the
-- cancellation date (needs the report) and - above all - the row set, which was
-- short by 13,196 opportunities until 2026-09-09.
--
-- Consumed via app_read, RLS-scoped by entity_id. Additive changes ship freely;
-- breaking changes require v2 with a 90-day overlap.
--
-- DELIBERATELY NARROW. core.opportunities has 60 columns; this exposes 39. A public
-- contract is cheap to widen and expensive to narrow - removing a column means a v2
-- and 90 days of running both - so the internal codes, the estimate breakdown, the
-- address, the affiliate and tariff fields and the raw referral string stay in core,
-- which app_read can also read under the "unstable" label. Ask for a column and it
-- is a one-line additive change.
--
-- TWO ROW-LEVEL EXCLUSIONS, both deliberate:
--
--   * is_deleted rows are out. A consumer of "opportunities" does not expect ones
--     the CRM has removed; the deletion ledger lives in core for anyone who does.
--   * is_in_scope = false rows are out. Those belong to the business that used the
--     `ld` SmartMoving account before 2025 - another company's data that a sweep to
--     2023 pulled in alongside ours. They are flagged in core and excluded from every
--     KPI mart; a PUBLIC contract must not carry them at all.
--
-- ⚠️ WHAT A CONSUMER MUST KNOW ABOUT THE DATES:
--
--   lead_received_date   Always present (97%). The cohort key.
--   booked_date          From the Booked report; covers its window, not all history.
--   cancelled_date       From the Cancellation Details report, window from 2026-01-02.
--                        NULL does NOT mean "not cancelled" - read is_cancelled.
--   service_date         Resolved from several sources; see core for the provenance.
--
-- ⚠️ quote_number is null on ~19% of rows. Those are report quotes the API has not
-- resolved yet; the quote_backfill drain closes them at ~3,600/day. The opportunity
-- is real and countable either way - only the quote linkage is pending.

with opps as (
    select * from {{ ref('opportunities') }}
    where not is_deleted
      and is_in_scope
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

agents as (
    select source_agent_name, agent_name, is_sales_agent
    from {{ ref('agents') }}
)

select
    o.opportunity_key,
    o.entity_id,
    o.source_instance_id,
    o.external_opportunity_id,
    o.quote_number,

    -- Who
    o.customer_name,
    o.customer_email,
    o.customer_phone,
    o.branch_name,
    -- Canonical roster name; falls back to the CRM's spelling for anyone unrostered.
    coalesce(a.agent_name, o.sales_assignee_name)       as agent_name,
    coalesce(a.is_sales_agent, true)                    as agent_is_sales_agent,

    -- Line of business, from the opportunity's jobs; provisional (from the branch)
    -- until it has one. `unassigned` only where neither exists.
    coalesce(l.line_of_business, 'unassigned')          as line_of_business,
    coalesce(l.is_provisional_line, true)               as line_is_provisional,

    -- Attribution. Individual campaign, then the family it rolls up to, then the
    -- channel. Three levels because all three questions get asked.
    o.referral_source_clean                             as referral_source,
    o.referral_campaign_group,
    o.referral_channel_group,
    o.referral_is_paid,

    -- Outcome. The flags come from the platform status integer via
    -- dim_opportunity_status; the label is for display, never for logic.
    o.status_label,
    o.status_category,
    o.status_subcategory,
    o.is_valid_lead,
    o.is_open,
    o.is_booked,
    o.is_completed,
    o.is_lost,
    o.is_bad_lead,
    o.is_cancelled,
    o.lost_reason,
    o.cancellation_reason,

    -- When
    o.created_date_local                                as lead_received_date,
    o.booked_date_local                                 as booked_date,
    o.service_date,
    o.cancelled_date_local                              as cancelled_date,
    o.time_to_first_contact_minutes,

    -- Money. Estimate is the quote; invoiced is what was billed; cancelled_amount
    -- is what the job was worth when it died. Three different claims.
    o.estimated_final_total,
    o.invoiced_amount,
    o.cancelled_amount,
    o.move_size_name,

    o.synced_at
from opps o
left join opportunity_line l
  on  l.source_instance_id      = o.source_instance_id
  and l.external_opportunity_id = o.external_opportunity_id
left join agents a
  on {{ norm_text('a.source_agent_name') }} = {{ norm_text('o.sales_assignee_name') }}
