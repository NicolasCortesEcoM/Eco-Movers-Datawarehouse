-- Last-observation-wins status per opportunity, from the WEBHOOK LOG ONLY
-- (Tier 0, zero API cost). Answers "how many opportunities do we have right now,
-- by status" in near real time, independent of any API call.
--
-- Grain: one row per (source_instance_id, external_opportunity_id).
--
-- Deliberately single-source. core.opportunities resolves status across all
-- sources; this model exists precisely to show what the FREE feed alone knows, so
-- the nightly reconciliation can compare the two and alert on divergence. Widening
-- it to other sources would destroy the thing it is for.
--
-- Now a filter over int_opportunity_observations rather than its own query, so the
-- webhook parsing logic lives in exactly one place.

with webhook_observations as (
    select *
    from {{ ref('int_opportunity_latest_by_source') }}
    where source = 'api_webhook'
)

select
    w.opportunity_key,
    w.entity_id,
    w.source_instance_id,
    w.external_opportunity_id,
    w.status_code                                       as opportunity_status_code,
    coalesce(s.status_name, 'status_' || w.status_code) as opportunity_status_label,
    s.status_category                                   as opportunity_status_category,
    coalesce(s.is_booked, false)                        as is_booked,
    coalesce(s.is_lost,   false)                        as is_lost,
    w.observed_at                                       as status_observed_at
from webhook_observations w
left join {{ ref('dim_opportunity_status') }} s
       on s.status_code = w.status_code
