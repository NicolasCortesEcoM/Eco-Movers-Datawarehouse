-- core.opportunity_payments - payments recorded against an opportunity.
-- Grain: (source_instance_id, external_opportunity_id, payment_seq).
--
-- Single-source like charges, so no observation layer.
--
-- The embedded payload carries no payment id, hence the ordinal in the grain.
-- GET /api/payments/opportunities/{id} would supply a real id plus jobId and
-- gatewayPaymentId, but costs one extra call per opportunity - not worth it while
-- payments appear on ~6% of opportunities. Revisit if payment reconciliation ever
-- needs to match a gateway record.

select
    p.payment_key,
    p.entity_id,
    p.source_instance_id,
    p.external_opportunity_id,
    p.payment_seq,
    p.payment_source_code,
    p.payment_type_code,
    p.payment_category_code,
    p.amount::numeric           as amount,
    p.amount_refunded::numeric  as amount_refunded,
    p.is_outstanding,
    p.taken_by_user,
    o.synced_at
from {{ ref('stg_smartmoving__opportunity_payments') }} p
left join {{ ref('opportunities') }} o
       on o.source_instance_id = p.source_instance_id
      and o.external_opportunity_id = p.external_opportunity_id
