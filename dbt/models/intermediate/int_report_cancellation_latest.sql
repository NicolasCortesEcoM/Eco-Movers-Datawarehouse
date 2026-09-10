-- Newest Cancellation Details report row per opportunity.
--
-- WHY THIS IS NOT AN OBSERVATION ARM. Same rule as int_report_all_jobs_latest and
-- int_report_lost_leads_latest: the observation layer resolves DISAGREEMENT, and it
-- earns its complexity only where two sources can report the same field.
--
-- WHEN a cancellation happened and HOW MUCH revenue it took with it have exactly one
-- source in this warehouse. There is nothing to reconcile. An observation arm would
-- mean adding two nullable columns to all seven other arms so each can contribute
-- NULL to them, to settle a conflict that cannot occur.
--
-- The one field that IS contested is the reason. The API carries a cancellation
-- reason on 219 of 6,331 cancelled opportunities (3.5%); this report carries one on
-- 1,476. core.opportunities settles that with pick_latest, so a fresher API answer
-- still wins on the rare opportunity that has both.
--
-- Resolves through the quote crosswalk: like every scheduled report this one is keyed
-- on Quote # and carries no GUID. 1,476 of its 1,477 quotes resolve. A report must
-- resolve against an API source, never against another report - quote numbers are
-- unique only WITHIN an instance.
--
-- ⚠️ COVERAGE IS A WINDOW, NOT HISTORY. The scheduled report starts at 2026-01-02, so
-- roughly 1,500 of the 6,331 cancellations in core get a date and the rest stay null.
-- Anything counted BY cancellation date is therefore a 2026-onwards series; anything
-- counted by lead cohort still covers all history, because the cancelled FLAG comes
-- from the status integer and not from this report. Do not read a null
-- cancelled_date as "not cancelled".
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

    -- WHEN. Exists in no other source. Without it "cancelled" cannot be put on a
    -- trend, counted per month, or compared against the booking that preceded it.
    r.cancelled_date_local          as cancelled_date,

    -- The revenue that walked.
    r.cancelled_amount,

    -- WHY, in the CRM's own words. Seven values, all clean.
    r.cancellation_reason,

    -- The customer's intended move date. Read by core.opportunities as ONE candidate
    -- among several for service_date, never on its own: a cancelled job's move date
    -- is a plan that did not happen.
    r.service_date_local            as service_date

from {{ ref('stg_smartmoving__report_cancellations') }} r
join {{ ref('int_opportunity_quote_crosswalk') }} x
  on  x.source_instance_id = r.source_instance_id
  and x.quote_number       = r.quote_number
order by opportunity_key, r.report_generated_at desc
