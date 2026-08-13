-- Payments recorded against an opportunity (IncludePayments on the detail call).
-- Grain: (source_instance_id, external_opportunity_id, payment_seq).
--
-- The embedded payload carries NO payment id, so the ordinal is the only key
-- available. GET /api/payments/opportunities/{id} would add id, jobId,
-- gatewayPaymentId and paidAtUtc - but at one extra call per opportunity, which is
-- not worth it while payments appear on only ~6% of opportunities. Revisit if
-- payment reconciliation ever needs the gateway id.
--
-- source, payment_type and payment_category are int enums, left unlabelled
-- pending a verified seed.
--
-- Money is cast to numeric here, at the staging boundary - see the note in
-- stg_smartmoving__opportunity_job_charges. dlt lands it as double precision;
-- typing it once here is what keeps "do not SUM money in staging" from being a
-- rule anyone has to remember.

with payments as (
    select * from {{ source('smartmoving', 'opportunities_enriched__payments') }}
),

opportunities as (
    select opportunity_dlt_id, source_instance_id, entity_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
)

select
    o.source_instance_id || ':' || o.external_opportunity_id || ':' || p._dlt_list_idx as payment_key,
    o.source_instance_id,
    o.entity_id,
    o.external_opportunity_id,
    p._dlt_list_idx                 as payment_seq,

    p.source                        as payment_source_code,
    p.payment_type                  as payment_type_code,
    p.payment_category              as payment_category_code,
    p.amount::numeric               as amount,
    p.amount_refunded::numeric      as amount_refunded,
    p.is_outstanding,
    nullif(p.taken_by_user, '')     as taken_by_user
from payments p
join opportunities o
  on o.opportunity_dlt_id = p._dlt_parent_id
