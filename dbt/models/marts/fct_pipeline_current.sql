-- The live pipeline, one row per unresolved opportunity, as of the last build.
--
-- THIS IS A SNAPSHOT OF NOW, NOT A TIME SERIES. It is rebuilt from scratch on every
-- dbt run, so it answers "what is in the pipeline today" and cannot answer "how did
-- the pipeline move last week". Making it a time series means an incremental model
-- that appends a dated snapshot per run - a real commitment, and this project has no
-- incremental models at all today. For 628 rows that is not yet worth it. When someone
-- actually needs week-over-week movement, that is the moment to build it, and this
-- model is the right thing to append.
--
-- ⚠️ CALIBRATE YOUR EXPECTATIONS BEFORE BUILDING A FORECAST ON THIS.
--
-- Measured 2026-09-08 on the live warehouse: 628 unresolved opportunities in total -
-- 411 booked and 217 open - of which 485 have a future service date. By service month
-- the whole thing is front-loaded and then falls off a cliff:
--
--     2026-09   258 booked ($678k)   85 open ($265k)
--     2026-10    53 booked ($188k)   51 open ($189k)
--     2026-11     6 booked ( $42k)   12 open ($673k)
--     2026-12+   single digits per month
--
-- This CRM does not hold a long open funnel; most opportunities resolve quickly. The
-- honest forecast horizon is about two months, and the real value here is **revenue
-- already committed** (booked, future-dated) rather than a speculative funnel.
--
-- THERE IS DELIBERATELY NO PROBABILITY-WEIGHTED FORECAST COLUMN. Weighting 162 open
-- opportunities by a historical conversion rate produces a number with the shape of a
-- forecast and the reliability of a coin flip, and it would be quoted as if it were
-- neither. Booked and open are reported separately so the reader does the weighting
-- consciously, or does not.
--
-- Grain: one row per (source_instance_id, external_opportunity_id).

{{ config(materialized='table') }}

with live as (
    select
        o.opportunity_key,
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.quote_number,
        o.customer_name,
        o.branch_name,
        o.sales_assignee_name,
        o.status_label,
        o.status_category,
        o.is_booked,
        o.is_open,
        o.referral_channel_group,
        o.referral_is_paid,
        o.service_date,
        o.service_date_source,
        o.created_date_local,
        o.estimated_final_total,
        o.invoiced_amount,
        o.timezone,
        o.synced_at
    from {{ ref('opportunities') }} o
    where not o.is_deleted
      -- Prior-tenant guard - see dim_instance.data_valid_from.
      and o.is_in_scope
      -- UNRESOLVED ONLY, and the filter is on the CATEGORY on purpose.
      --
      -- `is_booked` is NOT "is in the pipeline". It is true for Booked, Completed AND
      -- Closed, because all three mean the deal was won - that is what status_model.md
      -- means by "do not derive booked by string-matching the label". The first draft
      -- of this model wrote `is_open or is_booked` and pulled in 27,041 rows instead of
      -- 628: every finished job in the warehouse, presented as live pipeline. The
      -- accepted_values test on status_category caught it.
      and o.status_category in ('open', 'booked')
),

opportunity_line as (
    select * from {{ ref('int_opportunity_line') }}
)

select
    l.opportunity_key,
    l.entity_id,
    l.source_instance_id,
    l.external_opportunity_id,
    l.quote_number,
    l.customer_name,
    l.branch_name,
    l.sales_assignee_name,
    coalesce(ln.line_of_business, 'unassigned')        as line_of_business,
    l.referral_channel_group,
    l.referral_is_paid,

    l.status_label,
    l.status_category,
    -- The distinction the whole model exists for. Committed work and speculative work
    -- must never be summed into one "pipeline value" - that is the number that gets
    -- quoted in a meeting and then missed.
    l.is_booked                                        as is_committed,
    l.is_open                                          as is_speculative,

    l.service_date,
    l.service_date_source,
    -- Null when there is no service date at all (50 rows). Not zero: zero would sort
    -- and filter as "today", putting undated work into this week's numbers.
    case when l.service_date is not null
         then (l.service_date - {{ entity_today('coalesce(l.timezone, i.timezone)') }})
    end                                                as days_until_service,
    case when l.service_date is not null
         then to_char(l.service_date, 'YYYY-MM')
    end                                                as service_month,

    l.created_date_local,
    case when l.created_date_local is not null
         then ({{ entity_today('coalesce(l.timezone, i.timezone)') }} - l.created_date_local)
    end                                                as age_days,

    l.estimated_final_total,
    -- Carried for completeness, not as a forecast input: an unresolved opportunity
    -- has normally not been invoiced, so this is null on almost every row here.
    l.invoiced_amount,

    l.synced_at
from live l
-- The branch timezone can be null when no branch matched; falling back to the
-- instance zone keeps every derived date populated instead of silently nulling it.
left join {{ ref('dim_instance') }} i
       on i.instance_id = l.source_instance_id
left join opportunity_line ln
  on  ln.source_instance_id      = l.source_instance_id
  and ln.external_opportunity_id = l.external_opportunity_id
