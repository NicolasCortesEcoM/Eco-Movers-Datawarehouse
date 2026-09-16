-- core.payments must contain every row of the NEWEST Payments generation, per
-- instance, row for row and to the cent - the accumulative model may never hold less
-- than the latest export. It also must not hold FEWER rows than any earlier build
-- would have: the count of distinct payment days can only grow. (The first half is
-- the invariant; the second is what "accumulative" means operationally.)
with newest as (
    select r.source_instance_id, count(*) as n, sum(r.payment_amount) as amount
    from {{ ref('stg_smartmoving__report_payments') }} r
    join (select source_instance_id, max(report_generated_at) as g
          from {{ ref('stg_smartmoving__report_payments') }} group by 1) g
      on g.source_instance_id = r.source_instance_id and g.g = r.report_generated_at
    where r.payment_date_local is not null
    group by 1
),
in_core as (
    select source_instance_id, count(*) as n, sum(payment_amount) as amount
    from {{ ref('payments') }}
    where is_in_newest_generation
    group by 1
)
select n.source_instance_id, n.n as newest_rows, c.n as core_rows, n.amount, c.amount as core_amount
from newest n
left join in_core c on c.source_instance_id = n.source_instance_id
where c.n is distinct from n.n or abs(c.amount - n.amount) > 0.005
