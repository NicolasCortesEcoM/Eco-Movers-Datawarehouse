-- marts.fct_outstanding_balances - every opportunity whose money is not settled,
-- as of the last build. Grain: one row per opportunity with a non-zero balance.
--
-- WHY COMPUTED, NOT THE OUTSTANDING BALANCES REPORT (Nicolas, 2026-09-15). That report
-- is invoice total - payments per quote, plus `Invoice Sent At`. Everything but the
-- invoice timestamp is already here: `core.opportunities.invoiced_amount` is All Jobs'
-- Total Actual Cost, and `core.payments` now holds every payment since 2023. The
-- report is also a snapshot; this is the current state, rebuilt with every load,
-- which is what "who still owes us" means to a manager. Aging runs from the SERVICE
-- date because the invoice date is not available - fine for moves, which invoice on
-- the day; loose for storage, which bills monthly and is excluded here (no invoice
-- amount exists for a storage account in the warehouse).
--
-- THE INVOICE IS ALL JOBS' ACTUAL COST. `core.opportunities.invoiced_amount` is, since
-- 2026-09-15, the sum of the opportunity's jobs' Total Actual Cost (Booked report only
-- as a fallback) - Nicolas: revenue follows All Jobs, never Booked. A long-distance
-- move is two jobs (pickup, hourly, $0 + delivery, mileage-rated, the money), often
-- months apart, and the delivery-day collection is not always keyed into the CRM:
-- an LD opportunity is SETTLED when its status is Closed OR when payments reach the
-- All Jobs total. `is_delivery_pending` marks the LD rows still between those two.
--
-- BALANCE = invoiced - net paid. Net paid is sum(payment_amount): refunds subtract,
-- and a bounce and its reversed payment cancel each other, so a bounced check leaves
-- the balance open again by itself. Where the Payments report has never listed the
-- opportunity (ld before 2025-03) the API's embedded payments stand in
-- (`payment_source` = 'api'); `report` otherwise.
--
-- POPULATION AND KIND. Only opportunities whose job has happened can owe or be owed:
--   invoiced          the job has an actual cost (Completed / Closed, or Booked with
--                     the service date passed) -> balance vs that invoice
--   closed_no_invoice Completed / Closed but every job's actual cost is 0: money
--                     held against nothing SmartMoving priced - a data gap to fix in
--                     the CRM, not AR
--   service_not_closed Booked, service date passed, no actual cost yet: ops backlog
--   cancelled_paid    Cancelled with money still held      -> refund due
-- Commercial and 'Bill To Account' customers are invoiced outside SmartMoving (the
-- Payments report never sees the settlement), so their rows read as unpaid here
-- until QuickBooks is in the warehouse: `gross_paid = 0` on a 90+ commercial row
-- means "not in the CRM", not "not paid". Filter on it.
-- `balance_kind`: 'customer_owes' (> 0) or 'we_owe' (< 0, overpaid or cancelled and
-- paid). Audited 2026-09-15: 40 overpaid opportunities in 25,680 - most are
-- same-day invoices not yet closed out, four are duplicate-entry suspects (paid is
-- exactly twice the invoice; see `is_exact_double`).
--
-- Never sum `balance` across kinds without looking: 'we_owe' is negative on purpose.

{{ config(materialized='table') }}

with report_paid as (
    select
        source_instance_id,
        quote_number,
        sum(payment_amount)                                             as net_paid,
        sum(payment_amount) filter (where transaction_kind = 'payment') as gross_paid,
        -sum(payment_amount) filter (where transaction_kind = 'refund') as refunded,
        count(*) filter (where transaction_kind = 'bounce')             as bounces,
        max(payment_date_local) filter (where payment_amount > 0)       as last_payment_date,
        max(payment_date_local) filter (where transaction_kind = 'refund') as last_refund_date
    from {{ ref('payments') }}
    where quote_number is not null
    group by 1, 2
),

api_paid as (
    select
        source_instance_id,
        external_opportunity_id,
        sum(amount) - coalesce(sum(amount_refunded), 0)                 as net_paid,
        sum(amount)                                                     as gross_paid,
        coalesce(sum(amount_refunded), 0)                               as refunded
    from {{ ref('opportunity_payments') }}
    group by 1, 2
),

-- One aggregate pass over jobs, joined by key (a lateral per opportunity took minutes).
jobs_agg as (
    select
        source_instance_id,
        external_opportunity_id,
        max(job_number)                                     as job_number,
        max(completed_date_local)                           as completed_date_local,
        max(closed_date_local)                              as closed_date_local,
        count(*)                                            as job_count
    from {{ ref('jobs') }}
    where not is_deleted
    group by 1, 2
),

opps as (
    select
        o.*,
        coalesce(l.line_of_business, 'unassigned')          as line_of_business,
        j.completed_date_local,
        j.closed_date_local,
        j.job_number,
        j.job_count,
        o.invoiced_amount                                   as invoice_total
    from {{ ref('opportunities') }} o
    left join {{ ref('int_opportunity_line') }} l
      on  l.source_instance_id      = o.source_instance_id
      and l.external_opportunity_id = o.external_opportunity_id
    left join jobs_agg j
      on  j.source_instance_id      = o.source_instance_id
      and j.external_opportunity_id = o.external_opportunity_id
    where o.is_in_scope
      and not o.is_deleted
),

resolved as (
    select
        o.opportunity_key,
        o.entity_id,
        o.source_instance_id,
        o.external_opportunity_id,
        o.quote_number,
        o.job_number,
        o.customer_name,
        o.customer_phone,
        o.customer_email,
        o.branch_name,
        o.line_of_business,
        o.sales_assignee_name,
        o.status_label,
        o.service_date,
        o.completed_date_local,
        o.closed_date_local,
        o.invoice_total                                     as invoiced_amount,
        o.job_count,
        o.estimated_final_total,
        case
            when rp.quote_number is not null then 'report'
            when ap.external_opportunity_id is not null then 'api'
            else 'none'
        end                                                 as payment_source,
        coalesce(rp.net_paid,   ap.net_paid,   0)           as net_paid,
        coalesce(rp.gross_paid, ap.gross_paid, 0)           as gross_paid,
        coalesce(rp.refunded,   ap.refunded,   0)           as refunded,
        coalesce(rp.bounces, 0)                             as bounces,
        rp.last_payment_date,
        rp.last_refund_date,
        case
            when o.is_cancelled                             then 'cancelled_paid'
            when coalesce(o.invoice_total, 0) > 0
             and (o.status_label in ('Completed', 'Closed')
                  or (o.is_booked and o.service_date < current_date))
                                                            then 'invoiced'
            when o.status_label in ('Completed', 'Closed')  then 'closed_no_invoice'
            when o.is_booked and o.service_date < current_date
                                                            then 'service_not_closed'
            else                                                 'pre_service'
        end                                                 as population,
        o.synced_at
    from opps o
    left join report_paid rp
      on  rp.source_instance_id = o.source_instance_id
      and rp.quote_number       = o.quote_number
    left join api_paid ap
      on  ap.source_instance_id      = o.source_instance_id
      and ap.external_opportunity_id = o.external_opportunity_id
),

balanced as (
    select
        r.*,
        case
            when population = 'invoiced'         then invoiced_amount - net_paid
            when population = 'closed_no_invoice' then -net_paid
            when population = 'cancelled_paid'   then -net_paid
            when population = 'service_not_closed' then -net_paid
        end                                                 as balance,
        coalesce(completed_date_local, service_date)        as aging_from_date
    from resolved r
    where population in ('invoiced', 'closed_no_invoice', 'cancelled_paid', 'service_not_closed')
)

select
    opportunity_key                                         as balance_key,
    entity_id,
    source_instance_id,
    external_opportunity_id,
    quote_number,
    job_number,
    customer_name,
    customer_phone,
    customer_email,
    branch_name,
    line_of_business,
    sales_assignee_name,
    status_label,
    population,
    service_date,
    completed_date_local,
    aging_from_date,
    (current_date - aging_from_date)                        as days_outstanding,
    case
        when current_date - aging_from_date <= 30   then '01 0-30'
        when current_date - aging_from_date <= 60   then '02 31-60'
        when current_date - aging_from_date <= 90   then '03 61-90'
        else                                             '04 90+'
    end                                                     as aging_band,

    invoiced_amount,
    job_count,
    estimated_final_total,
    gross_paid,
    refunded,
    net_paid,
    bounces,
    balance,
    case when balance > 0 then 'customer_owes' else 'we_owe' end as balance_kind,
    (population = 'invoiced' and invoiced_amount > 0
     and abs(net_paid - 2 * invoiced_amount) < 1)           as is_exact_double,
    -- LD: picked up, not yet closed, money still due - the delivery leg is open.
    (line_of_business = 'long_distance' and status_label <> 'Closed' and balance > 0)
                                                            as is_delivery_pending,
    payment_source,
    last_payment_date,
    last_refund_date,
    synced_at
from balanced
where abs(balance) >= 1
