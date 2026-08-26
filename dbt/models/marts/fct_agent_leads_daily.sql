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
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.created_date_local is not null
      and not o.is_deleted
      and nullif(trim(o.sales_assignee_name), '') is not null
),

-- The line of business belongs to the JOB, and an opportunity can in principle have
-- jobs on more than one line. Five do, out of 15,028. `min` is not a judgement about
-- which line is right - it is a deterministic tie-break so the grain stays stable
-- across builds. Five rows do not justify a rule anyone has to remember.
opportunity_line as (
    select
        source_instance_id,
        external_opportunity_id,
        min(line_of_business)                       as line_of_business,
        count(distinct line_of_business) > 1        as has_mixed_lines
    from {{ ref('lines_of_business') }}
    group by 1, 2
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

        sum(estimated_final_total) filter (where is_booked)  as booked_estimated_value,
        sum(invoiced_amount)                                 as invoiced_value,

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

    a.booked_estimated_value,
    a.invoiced_value,
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
