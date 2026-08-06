-- One row per webhook event that reports an opportunity status, extracted from
-- the raw envelope. ZERO API cost: the status int rides inside the webhook
-- payload for every opportunity-* event (confirmed in the live log:
-- opportunity-created / opportunity-status-changed / opportunity-changed all
-- carry 'opportunity-id' + 'opportunity-status'). received_at is the observed
-- instant; int_opportunity_status_latest picks the newest per opportunity.
--
-- The status int here is the webhook/sweep coding, where only 4=Booked is stable
-- (see smartmoving_api_findings.md - the detail endpoint uses a different coding).
-- We surface the raw code; labelling waits on the dim_opportunity_status seed.
select
    entity_id,
    source_instance_id,
    payload ->> 'opportunity-id'                         as external_opportunity_id,
    (payload ->> 'opportunity-status')::int              as opportunity_status_code,
    event_type,
    received_at                                          as observed_at
from {{ source('smartmoving', 'webhook_events') }}
where payload ? 'opportunity-id'
  and payload ? 'opportunity-status'
