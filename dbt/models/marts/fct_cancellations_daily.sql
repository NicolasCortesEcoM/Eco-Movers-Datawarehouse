-- marts.fct_cancellations_daily - cancellations counted on the day they HAPPENED.
-- Grain: one row per (entity_id, agent_name, line_of_business, cancelled_date).
--
-- THE SECOND OF TWO CANCELLATION VIEWS, AND THEY ANSWER DIFFERENT QUESTIONS. Reading
-- one for the other is the easiest mistake to make here, so:
--
--   fct_agent_leads_daily.cancellation_pct   COHORT. Keyed on the day the lead
--                                            ARRIVED. "Of the deals born on this day
--                                            and later won, how many fell through?"
--                                            The cancellation may have happened
--                                            months later. Use it to judge intake
--                                            quality and an agent's hold rate.
--
--   THIS MODEL                               PERIOD. Keyed on the day the deal was
--                                            CANCELLED. The lead may be from any
--                                            earlier month. "How much did we lose in
--                                            October?" Use it for trend, for
--                                            operational load, and for revenue that
--                                            walked in a window.
--
-- A cancellation appears in exactly one row of each, on two different dates. Summing
-- the two together double counts.
--
-- ⚠️ WINDOW, NOT HISTORY. cancelled_date comes from the Cancellation Details report,
-- which starts 2026-01-02. This model therefore covers 1,476 of the 6,331
-- cancellations in core - the ones with a known date. The cohort view has no such
-- limit, because the cancelled FLAG comes from the status integer and covers every
-- year. If the two disagree on a total, this is why.
--
-- No rate is published here, deliberately. A rate needs a denominator, and the deals
-- that were bookable on a given calendar day are not knowable from this grain - they
-- were booked across many previous months. Rates live in the cohort model, where the
-- denominator is real. This model reports counts and money.

{{ config(materialized='table') }}

with cancelled as (
    select
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.sales_assignee_name,
        o.cancelled_date_local              as cancelled_date,
        o.created_date_local                as lead_received_date,
        o.cancelled_amount,
        o.invoiced_amount,
        o.estimated_final_total,
        o.cancellation_reason,
        o.booked_date_local,
        o.synced_at
    from {{ ref('opportunities') }} o
    where o.is_cancelled
      and o.cancelled_date_local is not null
      and not o.is_deleted
      -- Prior-tenant guard, same as every other KPI mart. See dim_instance.
      and o.is_in_scope
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
),

agents as (
    select source_agent_name, agent_name, is_sales_agent, role
    from {{ ref('agents') }}
),

joined as (
    select
        -- An unassigned cancellation is kept under a literal rather than dropped, so
        -- the model still reconciles against core. Dropping it would make the loss
        -- disappear rather than making it visible.
        coalesce(a.agent_name, nullif(trim(c.sales_assignee_name), ''), 'unassigned')
                                                                 as agent_name,
        coalesce(a.is_sales_agent, true)                         as is_sales_agent,
        a.role,
        coalesce(l.line_of_business, 'unassigned')               as line_of_business,
        c.*
    from cancelled c
    left join opportunity_line l
      on  l.source_instance_id      = c.source_instance_id
      and l.external_opportunity_id = c.external_opportunity_id
    left join agents a
      on {{ norm_text('a.source_agent_name') }} = {{ norm_text('c.sales_assignee_name') }}
),

aggregated as (
    select
        entity_id,
        agent_name,
        is_sales_agent,
        role,
        line_of_business,
        cancelled_date,

        count(*)                                          as cancellations,

        -- The revenue that walked, as the CRM stated it on the cancellation itself.
        -- Kept separate from invoiced_value because they are different claims: one is
        -- what the job was worth when it died, the other is what was actually billed.
        sum(cancelled_amount)                             as cancelled_value,
        sum(invoiced_amount)                              as invoiced_value_at_cancellation,

        -- How long the deal survived between booking and cancelling. Null for the
        -- rows with no booked date rather than zero, so the average is not dragged
        -- down by unknowns.
        avg(cancelled_date - booked_date_local)
            filter (where booked_date_local is not null)  as avg_days_booked_before_cancelling,
        count(booked_date_local)                          as cancellations_with_booked_date,

        -- The oldest and newest lead behind this day's cancellations. Cheap, and it
        -- makes the cohort/period distinction visible in the data itself.
        min(lead_received_date)                           as oldest_lead_cancelled,
        max(lead_received_date)                           as newest_lead_cancelled,

        max(synced_at)                                    as synced_at
    from joined
    group by 1, 2, 3, 4, 5, 6
)

select
    -- Plain concatenation, not a hash. dbt_utils is deliberately not installed in
    -- this project, and a readable key is easier to debug in Metabase anyway.
    entity_id || ':' || agent_name || ':' || line_of_business || ':' || cancelled_date
                                                          as cancellation_day_key,
    entity_id,
    agent_name,
    is_sales_agent,
    role,
    line_of_business,
    cancelled_date,
    cancellations,
    cancelled_value,
    invoiced_value_at_cancellation,
    round(avg_days_booked_before_cancelling, 1)           as avg_days_booked_before_cancelling,
    cancellations_with_booked_date,
    oldest_lead_cancelled,
    newest_lead_cancelled,
    synced_at
from aggregated
