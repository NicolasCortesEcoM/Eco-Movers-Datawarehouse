-- Sales performance, one row per (agent, line of business, day the lead arrived).
--
-- THE GRAIN IS A COHORT, AND THAT IS THE WHOLE DESIGN DECISION.
--
-- A row says: "of the leads that reached THIS agent, for THIS line, on THIS day,
-- here is what became of them." Every number on the row is about that group of
-- leads, no matter when the outcome happened. A lead received in March and booked
-- in May counts on the March row.
--
-- That is what makes conversion answerable. The alternative grain - "what happened
-- ON this day" - cannot produce a conversion rate at all, because the leads and the
-- bookings on any given day belong to different populations. Mixing the two in one
-- row is the classic way a sales dashboard ends up with a rate nobody can reproduce.
--
-- "How much did we book in July" is a real question and this is NOT the table for
-- it. It needs the booking date as its grain and gets its own model when someone
-- actually asks. Two small honest tables beat one that quietly answers both wrong.
--
-- ⚠️ RECENT COHORTS ARE NOT COMPARABLE TO OLD ONES. A lead that arrived yesterday
-- has not had time to be lost yet, so its cohort looks far more successful than it
-- will end up. August 2026 read 71% against a 45-50% baseline for exactly this
-- reason. `open_leads` is carried on every row so this is visible rather than
-- inferred: a cohort with open leads left is still settling. Any conversion figure
-- shown to a person should either exclude the last ~60 days or display open_leads
-- beside it.
--
-- Materialised as a table: it is small (a few thousand rows), read repeatedly by BI,
-- and built from a join no one wants re-run per query.

{{ config(materialized='table') }}

with opps as (
    select
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.sales_assignee_name,
        o.created_date_local                as lead_received_date,
        o.is_valid_lead,
        o.is_bad_lead,
        o.is_booked,
        o.is_lost,
        o.is_open,
        o.is_cancelled,
        o.estimated_final_total,
        o.invoiced_amount,
        o.time_to_first_contact_minutes,
        o.lost_reason,
        o.status_subcategory,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.created_date_local is not null
      and not o.is_deleted
      -- Prior-tenant guard. The `ld` SmartMoving account belonged to another business
      -- before 2025 and a sweep back to 2023 pulled 3,170 of their opportunities in.
      -- Almost none carry a sales agent, so the filter below already excluded most of
      -- them by accident - this makes it deliberate, and survives the roster being
      -- completed. See dim_instance.data_valid_from.
      and o.is_in_scope
      and nullif(trim(o.sales_assignee_name), '') is not null
),

-- Shared with fct_lead_source_daily; the tie-break reasoning lives in the model.
opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

-- Canonical identity, and the roster's own answer to "is this a salesperson".
-- Shared CRM accounts (`Admin team`, `Seattle Operations Team`) are people-shaped in
-- the data and are not people. They are kept and flagged, never dropped: a silent
-- exclusion is indistinguishable from a bug when the totals do not add up.
agents as (
    select
        source_agent_name,
        agent_name,
        is_sales_agent,
        role
    from {{ ref('agents') }}
),

joined as (
    select
        coalesce(a.agent_name, o.sales_assignee_name)            as agent_name,
        coalesce(a.is_sales_agent, true)                         as is_sales_agent,
        a.role,
        -- An opportunity with no job has no line. It is attributed to `unassigned`
        -- rather than dropped, so the agent's total still reconciles against
        -- core.opportunities and the gap is visible instead of missing.
        coalesce(l.line_of_business, 'unassigned')               as line_of_business,
        coalesce(l.has_mixed_lines, false)                       as has_mixed_lines,
        o.*
    from opps o
    left join opportunity_line l
      on  l.source_instance_id       = o.source_instance_id
      and l.external_opportunity_id  = o.external_opportunity_id
    left join agents a
      on {{ norm_text('a.source_agent_name') }} = {{ norm_text('o.sales_assignee_name') }}
),

aggregated as (
    select
        entity_id,
        agent_name,
        is_sales_agent,
        role,
        line_of_business,
        lead_received_date,

        count(*)                                          as leads_received,
        count(*) filter (where is_valid_lead)             as valid_leads,
        count(*) filter (where is_bad_lead)               as bad_leads,

        count(*) filter (where is_booked)                 as booked_leads,
        count(*) filter (where is_lost)                   as lost_leads,
        count(*) filter (where is_cancelled)              as cancelled_leads,
        -- The maturity signal. A cohort with open leads has not finished settling.
        count(*) filter (where is_open)                   as open_leads,

        count(*) filter (where has_mixed_lines)           as mixed_line_leads,

        -- NO `quoted_leads` HERE, deliberately. The obvious definition - an
        -- opportunity that carries an estimate - measures nothing: the Lead Status
        -- report emits `Estimated Revenue` on every row, so it is never null, and a
        -- positive value does not mean a quote was given. Measured 2026-09-08:
        -- opportunities with a zero estimate convert at 50.0% and those with a
        -- positive one at 48.9%. If a positive estimate meant "quoted", those two
        -- numbers would not be the same. The quoting step is not observable in this
        -- data and a column pretending otherwise is worse than its absence.

        sum(estimated_final_total) filter (where is_booked)  as booked_estimated_value,
        -- REALISED revenue, not the estimate. `estimated_final_total` is never null
        -- but is ZERO on 45% of booked opportunities, so averaging it reports $1,151
        -- against a true $2,085 - understated by nearly half, and silently. Measured
        -- 2026-09-08 on 26,614 booked leads: invoiced_amount is present on 96% of
        -- them and is what the customer was actually billed.
        sum(invoiced_amount)                                 as invoiced_value,
        count(*) filter (where invoiced_amount > 0)          as invoiced_deals,

        -- WHY the losses happened, from dim_status_map's subcategory. This is the
        -- half of the funnel a conversion rate cannot explain, and it only became
        -- answerable once that seed was finally joined: lost-reason coverage went
        -- from 56.6% to 95.6% of lost opportunities on 2026-09-08.
        count(*) filter (where is_lost and status_subcategory = 'lost_competitor') as lost_to_competitor,
        count(*) filter (where is_lost and status_subcategory = 'lost_price')      as lost_on_price,
        count(*) filter (where is_lost and status_subcategory = 'lost_contact')    as lost_no_contact,
        count(*) filter (where is_lost and status_subcategory = 'lost_diy')        as lost_to_diy,
        count(*) filter (where is_lost and status_subcategory is null)             as lost_reason_unknown,

        -- Only the Lost Leads report carries this, so it is populated for lost
        -- records and null elsewhere. Averaged over the rows that have it.
        avg(time_to_first_contact_minutes)                as avg_minutes_to_first_contact,
        count(time_to_first_contact_minutes)              as leads_with_contact_timing,

        -- Inherited, not now(): it answers "how fresh is the data behind this
        -- row", which a build timestamp would overstate every single build.
        max(synced_at)                                    as synced_at
    from joined
    group by 1, 2, 3, 4, 5, 6
)

select
    -- Plain concatenation rather than a hash: the key is readable in a BI tool, and
    -- the repo has no dbt_utils dependency to add for one function.
    a.entity_id || ':' || a.agent_name || ':' || a.line_of_business
                || ':' || to_char(a.lead_received_date, 'YYYYMMDD')
                                                          as agent_day_key,
    a.entity_id,
    a.agent_name,
    a.is_sales_agent,
    a.role,
    a.line_of_business,
    a.lead_received_date,

    a.leads_received,
    a.valid_leads,
    a.bad_leads,
    a.booked_leads,
    a.lost_leads,
    a.cancelled_leads,
    a.open_leads,
    a.mixed_line_leads,

    -- Conversion is expressed against VALID leads, not against everything received.
    -- A bad lead - a wrong number, a spam form fill - was never winnable, and
    -- counting it against the agent makes the rate a measure of lead quality rather
    -- than of selling. Null rather than zero when there is no denominator: zero
    -- would average into a report as if it were a real 0% performance.
    case when a.valid_leads > 0
         then round(100.0 * a.booked_leads / a.valid_leads, 1)
    end                                                   as conversion_pct,

    -- Over the deals that actually have a figure, not over all booked deals: a
    -- missing invoice is "not billed yet", and dividing by it would report a
    -- shrinking deal size every time a new booking lands. Null, not zero, with no
    -- denominator - a zero averages into a report as a real result.
    case when a.invoiced_deals > 0
         then round(a.invoiced_value / a.invoiced_deals, 2)
    end                                                   as avg_invoiced_deal_size,
    a.invoiced_deals,

    a.booked_estimated_value,
    a.invoiced_value,

    a.lost_to_competitor,
    a.lost_on_price,
    a.lost_no_contact,
    a.lost_to_diy,
    a.lost_reason_unknown,

    a.avg_minutes_to_first_contact,
    a.leads_with_contact_timing,

    -- Did this lead land in a line the agent is actually assigned to on that date?
    -- Not a filter and not a correction - the fact records what happened. It is a
    -- data-quality signal: a run of `false` means either the roster is out of date
    -- or work is being routed somewhere unexpected, and both are worth knowing.
    coalesce(asg.agent_name is not null, false)           as is_within_assignment,

    a.synced_at
from aggregated a
left join {{ ref('dim_agent_assignment') }} asg
  on  {{ norm_text('asg.agent_name') }} = {{ norm_text('a.agent_name') }}
  and asg.line_of_business              = a.line_of_business
  and a.lead_received_date             >= asg.valid_from
  and a.lead_received_date             <= asg.valid_to
