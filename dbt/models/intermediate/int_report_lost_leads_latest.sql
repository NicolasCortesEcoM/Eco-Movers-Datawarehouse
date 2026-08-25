-- Newest Lost Leads report row per opportunity.
--
-- WHY THIS IS NOT AN OBSERVATION ARM. Same rule as int_report_all_jobs_latest: the
-- observation layer exists to resolve DISAGREEMENT, and it earns its complexity only
-- where two sources can report the same field.
--
-- The fields this report uniquely contributes - WHY a deal was lost, WHEN it was
-- lost, and how long the customer waited for a first reply - have exactly one source
-- in the warehouse. There is nothing to reconcile. Giving them an observation arm
-- would mean adding three nullable columns to all six other arms so that each can
-- contribute NULL to them, to settle a conflict that cannot occur.
--
-- So: one source, one winner per row -> `distinct on`, joined straight into
-- core.opportunities. `Move Date` is the exception and is handled there, because
-- service_date genuinely does have competing sources.
--
-- Resolves through the quote crosswalk: like every scheduled report, this one is
-- keyed on Quote # and carries no GUID. A report must resolve against an API source,
-- never against another report - quote numbers are unique only WITHIN an instance.
--
-- API quota cost: ZERO.

{{ config(materialized='view') }}

select distinct on (opportunity_key)
    r.source_instance_id || ':' || x.external_opportunity_id as opportunity_key,
    r.source_instance_id,
    r.entity_id,
    x.external_opportunity_id,
    r.quote_number,
    r.report_generated_at           as observed_at,

    -- Why the deal was lost, in the CRM's own words ("Lost price too high"). No
    -- other free source carries it, and the API gives it one opportunity at a time.
    r.lost_reason,
    r.lost_date_local               as lost_date,

    -- The gap between the lead arriving and someone answering it. The one number a
    -- sales team can act on directly.
    r.time_to_first_contact_minutes,

    -- Move Date. Read from here by core.opportunities as ONE candidate among
    -- several for service_date - it is not authoritative on its own, because a lost
    -- lead's intended move date is a customer's plan, not a booked commitment.
    r.service_date_local            as service_date,

    r.estimated_amount

from {{ ref('stg_smartmoving__report_lost_leads') }} r
join {{ ref('int_opportunity_quote_crosswalk') }} x
  on  x.source_instance_id = r.source_instance_id
  and x.quote_number       = r.quote_number
order by opportunity_key, r.report_generated_at desc
