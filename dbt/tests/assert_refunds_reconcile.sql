-- fct_refunds_daily must carry every refund and every bounce in core.payments, to
-- the cent, and its collected_amount must equal every positive payment.
with m as (
    select sum(refund_amount) as refunds, sum(bounced_amount) as bounces,
           sum(collected_amount) as collected
    from {{ ref('fct_refunds_daily') }}
),
c as (
    select -sum(payment_amount) filter (where transaction_kind = 'refund') as refunds,
           -sum(payment_amount) filter (where transaction_kind = 'bounce') as bounces,
            sum(payment_amount) filter (where transaction_kind = 'payment') as collected
    from {{ ref('payments') }}
)
select * from m, c
where abs(m.refunds - c.refunds) > 0.005
   or abs(m.bounces - c.bounces) > 0.005
   or abs(m.collected - c.collected) > 0.005
