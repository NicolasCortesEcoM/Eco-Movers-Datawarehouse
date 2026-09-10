-- serving.cancellations_daily_v1 - PUBLIC CONTRACT (Sales / Operations).
--
-- Cancellations counted on the day they HAPPENED, per agent and line of business.
-- Consumed via app_read, RLS-scoped by entity_id. Additive changes ship freely;
-- breaking changes require v2 with a 90-day overlap.
--
-- ⚠️ THIS IS THE PERIOD VIEW. IT IS NOT THE RATE.
--
-- A row says "on this date, this agent lost this many booked deals". The leads behind
-- them were received across many earlier months - `oldest_lead_cancelled` and
-- `newest_lead_cancelled` show the spread on every row.
--
-- For a cancellation RATE, use serving.sales_agent_daily_v1.cancellation_pct. It is
-- keyed on the day the lead ARRIVED, which is the only grain where the denominator -
-- the deals that could have cancelled - is knowable. A rate cannot be computed from
-- this table: the deals bookable on a given calendar day were booked across months
-- that this grain does not carry, so any denominator you build here is wrong.
--
-- The two views count the same cancellation on two different dates. Do not sum them.
--
-- ⚠️ COVERAGE STARTS 2026-01-02. cancelled_date comes from the Cancellation Details
-- scheduled report, whose window begins there. This view therefore holds 1,476 of the
-- 6,331 cancellations in core - every one with a known date. The cohort view counts
-- all 6,331, because the cancelled flag comes from the status integer, not from this
-- report. A total that disagrees with the cohort view is not a bug; it is this.
--
-- Prior-tenant rows are already excluded upstream (core.opportunities.is_in_scope).

select
    cancellation_day_key,
    entity_id,
    agent_name,
    is_sales_agent,
    role,
    line_of_business,
    cancelled_date,

    cancellations,

    -- What the job was worth when it died, as the CRM stated it on the cancellation.
    cancelled_value,
    -- What had actually been billed. A different claim, deliberately kept apart.
    invoiced_value_at_cancellation,

    -- How long the deal survived after booking. Null where the booked date is
    -- unknown; `cancellations_with_booked_date` says how much of the row it covers.
    avg_days_booked_before_cancelling,
    cancellations_with_booked_date,

    -- The span of lead dates behind this day's cancellations - the period/cohort
    -- distinction, visible in the row itself.
    oldest_lead_cancelled,
    newest_lead_cancelled,

    synced_at
from {{ ref('fct_cancellations_daily') }}
