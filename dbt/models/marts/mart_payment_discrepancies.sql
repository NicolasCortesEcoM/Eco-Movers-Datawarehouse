-- marts.mart_payment_discrepancies - opportunities whose money does not add up,
-- for someone to fix IN SMARTMOVING. Grain: one row per (opportunity, discrepancy).
--
-- Nicolas, 2026-09-15: "when these cases appear I want to see them in a view - never
-- exclude them automatically; a double-entered payment is an accounting error that
-- makes SmartMoving show revenue that does not exist." So this is a work queue, not
-- a metric: every row is a thing to correct in the CRM, and the row disappears on
-- the next build once it is corrected there. Nothing upstream is filtered by it.
--
-- Discrepancy kinds, worst first:
--   duplicate_entry_suspect  paid is EXACTLY twice the invoice, or the same amount
--                            was taken twice the same day by a keyed-in method
--                            (Check / E-Check / Cash / Zelle - no processor id) and
--                            the total exceeds the invoice. Audited 2026-09-15: 4.
--   overpaid                 paid exceeds the invoice by more than $1 and it is not
--                            the case above - a tip or extra not invoiced, or an
--                            invoice reduced after payment. Audited: ~14.
--   paid_no_invoice          Completed / Closed with money taken and every job's
--                            actual cost at zero - the job was never priced out.
--   cancelled_holding_money  Cancelled with net payments > 0 - a refund is due.
--   bounce_not_recollected   a bounced Check / E-Check with no later payment on the
--                            same opportunity - the customer still owes it.
-- Amounts are positive "how far off" figures; `balance` is the signed AR figure the
-- balances mart would show.

{{ config(materialized='table') }}

with bal as (
    select * from {{ ref('fct_outstanding_balances') }}
),

-- Same-day, same-amount, keyed-in duplicates (no processor confirmation to tell
-- them apart), on opportunities that end up overpaid.
same_day_pairs as (
    select
        p.source_instance_id, p.quote_number,
        p.payment_date_local, p.payment_amount, p.payment_method,
        count(*)                                            as copies
    from {{ ref('payments') }} p
    where p.transaction_kind = 'payment'
      and p.quote_number is not null
      and p.payment_method in ('Check', 'E-Check', 'Cash', 'Zelle', 'Bill To Account')
      and coalesce(p.cc_confirmation_code, '') = ''
    group by 1, 2, 3, 4, 5
    having count(*) > 1
),

bounces_open as (
    select b.source_instance_id, b.quote_number,
           -b.payment_amount as amount, b.payment_date_local
    from {{ ref('payments') }} b
    where b.transaction_kind = 'bounce'
      and b.quote_number is not null
      and not exists (
          select 1 from {{ ref('payments') }} p
          where p.source_instance_id = b.source_instance_id
            and p.quote_number       = b.quote_number
            and p.transaction_kind   = 'payment'
            and p.payment_date_local > b.payment_date_local)
),

rows_ as (
    select
        b.*,
        'duplicate_entry_suspect'                           as discrepancy,
        -b.balance                                          as amount_off,
        case when b.is_exact_double then 'paid is exactly 2x the invoice'
             else 'same amount taken twice the same day by ' || sp.payment_method end
                                                            as detail
    from bal b
    left join same_day_pairs sp
      on  sp.source_instance_id = b.source_instance_id
      and sp.quote_number       = b.quote_number
    where b.population = 'invoiced' and b.balance < -1
      and (b.is_exact_double or sp.quote_number is not null)

    union all

    select
        b.*,
        'overpaid',
        -b.balance,
        'paid ' || b.net_paid || ' against invoice ' || b.invoiced_amount
    from bal b
    where b.population = 'invoiced' and b.balance < -1
      and not b.is_exact_double
      and not exists (select 1 from same_day_pairs sp
                      where sp.source_instance_id = b.source_instance_id
                        and sp.quote_number = b.quote_number)

    union all

    select b.*, 'paid_no_invoice', -b.balance,
           'status ' || b.status_label || ', jobs actual cost 0, paid ' || b.net_paid
    from bal b where b.population = 'closed_no_invoice'

    union all

    select b.*, 'cancelled_holding_money', -b.balance,
           'cancelled, net payments ' || b.net_paid || ' not refunded'
    from bal b where b.population = 'cancelled_paid'

    union all

    select b.*, 'bounce_not_recollected', bo.amount,
           'bounced ' || bo.amount || ' on ' || bo.payment_date_local || ', no payment since'
    from bal b
    join bounces_open bo
      on  bo.source_instance_id = b.source_instance_id
      and bo.quote_number       = b.quote_number
)

select
    balance_key || ':' || discrepancy                       as discrepancy_key,
    entity_id,
    source_instance_id,
    external_opportunity_id,
    quote_number,
    job_number,
    customer_name,
    branch_name,
    line_of_business,
    sales_assignee_name,
    status_label,
    service_date,
    discrepancy,
    detail,
    amount_off,
    invoiced_amount,
    gross_paid,
    refunded,
    net_paid,
    balance,
    last_payment_date,
    synced_at
from rows_
