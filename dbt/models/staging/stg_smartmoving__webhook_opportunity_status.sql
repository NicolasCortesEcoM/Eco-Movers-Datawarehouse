-- One row per webhook event that reports an opportunity status, extracted from
-- the raw envelope. ZERO API cost: the status int rides inside the webhook
-- payload for every opportunity-* event (confirmed in the live log:
-- opportunity-created / opportunity-status-changed / opportunity-changed all
-- carry 'opportunity-id' + 'opportunity-status'). received_at is the observed
-- instant; int_opportunity_status_latest picks the newest per opportunity.
--
-- The status int is the SAME enum everywhere. The earlier note here (and in
-- smartmoving_api_findings.md) claimed the webhook/sweep coding differed from the
-- detail endpoint's and that only 4=Booked was stable. That was measured and
-- disproved: across all 657 enriched opportunities the sweep and detail values are
-- identical (4=4, 30=30, 20=20, 3=3, 10=10, 50=50, 11=11). Labels and flags come
-- from the dim_opportunity_status seed. See status_model.md.
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
