-- The newest Lead Status generation per opportunity, for the ONE field that report
-- carries and nothing else does for every lead: `Time to Contact`.
--
-- Everything else in Lead Status already reaches core through the observation layer
-- (report_lead_status arm of int_opportunity_observations). Time-to-contact is not
-- routed that way because it is single-source in practice - the Lost Leads report
-- carries the same measure for lost leads only, and Lead Status carries it for ALL
-- outcomes (99% of leads since 2025: lost, closed, cancelled, booked). Before this
-- model existed, core.opportunities.time_to_first_contact_minutes came from Lost Leads
-- alone, so "did slow first contact cause the cancellation" could not even be asked:
-- no cancelled or booked lead had the number.
--
-- Same shape as int_report_lost_leads_latest: newest generation wins per opportunity.
-- Zero API quota.

{{ config(materialized='view') }}

select distinct on (opportunity_key)
    r.source_instance_id || ':' || x.external_opportunity_id as opportunity_key,
    r.source_instance_id,
    r.entity_id,
    x.external_opportunity_id,
    r.quote_number,
    r.report_generated_at           as observed_at,
    r.time_to_contact_minutes,
    r.received_at_utc
from {{ ref('stg_smartmoving__report_lead_status') }} r
join {{ ref('int_opportunity_quote_crosswalk') }} x
  on  x.source_instance_id = r.source_instance_id
  and x.quote_number       = r.quote_number
where r.time_to_contact_minutes is not null
order by opportunity_key, r.report_generated_at desc
