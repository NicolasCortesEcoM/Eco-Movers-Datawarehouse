-- marts.fct_refunds_daily - money returned to customers, next to money collected,
-- one row per (entity, line of business, branch, payment method, day).
--
-- WHY DAILY (Nicolas, 2026-09-15: "weekly or monthly refund reports later"). A daily
-- base rolls up to any calendar - ISO week, month, quarter, a fiscal period that does
-- not start on the 1st - while a monthly base can never be re-cut into weeks. The
-- row count is small (a few thousand rows a year) so there is no cost to it. Weekly
-- and monthly reports are GROUP BYs over this table in Metabase; never a new model.
--
-- WHAT COUNTS AS A REFUND. core.payments classifies every negative row (see
-- int_report_payments_all): `refund` is money returned to the customer; `bounce` is a
-- Check / E-Check that exactly reversed an earlier payment - a collection failure, not
-- a return. Bounces are reported on their own columns and are NOT in refund_amount:
-- a refund rate that included them would blame sales for the bank. `zero` rows are
-- ignored. `refunds_full` counts refunds that returned a whole earlier payment (a
-- cancelled deposit, typically) as opposed to a partial credit.
--
-- The refund is dated on the day the refund was ISSUED, and the line of business is
-- the opportunity's. Storage-account refunds have no opportunity and no line: they
-- show as line 'storage'. `collected_amount` on the same row is what was taken that
-- day by that method, so refund_rate = refunds / collected is available at any grain
-- (sum both, then divide - never average the daily rate).

{{ config(materialized='table') }}

with p as (
    select
        p.*,
        case
            when p.payment_target = 'storage_account' then 'storage'
            else coalesce(l.line_of_business, 'unassigned')
        end                                                 as line_of_business
    from {{ ref('payments') }} p
    left join {{ ref('int_opportunity_line') }} l
      on  l.source_instance_id      = p.source_instance_id
      and l.external_opportunity_id = p.external_opportunity_id
    where p.transaction_kind <> 'zero'
)

select
    entity_id || ':' || line_of_business || ':' || coalesce(branch_name, '(none)')
        || ':' || coalesce(payment_method, '(none)')
        || ':' || to_char(payment_date_local, 'YYYYMMDD')     as refund_day_key,
    entity_id,
    line_of_business,
    branch_name,
    payment_method,
    payment_date_local                                        as activity_date,
    date_trunc('week',  payment_date_local)::date             as activity_week,
    date_trunc('month', payment_date_local)::date             as activity_month,

    count(*) filter (where transaction_kind = 'payment')      as payments,
    coalesce(sum(payment_amount) filter (where transaction_kind = 'payment'), 0)
                                                              as collected_amount,

    count(*) filter (where transaction_kind = 'refund')       as refunds,
    count(*) filter (where transaction_kind = 'refund' and is_full_reversal)
                                                              as refunds_full,
    coalesce(-sum(payment_amount) filter (where transaction_kind = 'refund'), 0)
                                                              as refund_amount,
    count(distinct coalesce(quote_number, storage_account_number))
        filter (where transaction_kind = 'refund')            as refunded_accounts,

    count(*) filter (where transaction_kind = 'bounce')       as bounces,
    coalesce(-sum(payment_amount) filter (where transaction_kind = 'bounce'), 0)
                                                              as bounced_amount,

    coalesce(sum(payment_amount), 0)                          as net_cash,
    max(synced_at)                                            as synced_at
from p
group by 1, 2, 3, 4, 5, 6, 7, 8
