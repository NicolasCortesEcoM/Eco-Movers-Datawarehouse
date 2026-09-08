-- The Payments scheduled report, typed.
--
-- WHY IT MATTERS: this is the only per-payment record anywhere in the warehouse.
-- `core.opportunities.invoiced_amount` is one realised total per opportunity; this is
-- the individual transactions behind it - date, amount, category, method. Cash timing,
-- deposit-versus-balance behaviour and payment-method mix are all unanswerable without
-- it, and it has been landing unread since 2026-08.
--
-- ⚠️ A PAYMENT ATTACHES TO ONE OF THREE THINGS, AND STORAGE IS NOT AN OPPORTUNITY.
--
-- Storage accounts are a THIRD top-level entity alongside opportunities and jobs.
-- Measured on all 162,660 landed rows, 2026-09-08:
--
--     130,171  Quote only                        -> opportunity payment
--      13,988  Quote AND Job                     -> opportunity payment
--      18,501  Storage Account, no quote or job  -> storage payment, NO opportunity
--           0  Job without a Quote
--           0  none of the three
--
-- Note the two zeroes, because they change the shape of the problem. **There is no
-- such thing as a job-only payment in this data.** `Job` is a refinement of a payment
-- that already belongs to an opportunity, not an alternative target - so the real
-- split today is two-way, opportunity versus storage. The `job` branch below is kept
-- as a defensive arm and has never fired; if it ever does, that is a genuine change in
-- vendor behaviour worth seeing rather than a case to silently fold into
-- 'opportunity'.
--
-- What matters is the storage third. Forcing every payment under an opportunity id -
-- the obvious shortcut - would silently drop 18,501 storage payments, $8.9M and 11% of
-- the cash, and the remaining total would still look entirely plausible.
-- `crm_sync_contract.md` has warned about this since the report was first wired; this
-- model is the first thing to honour the warning.
--
-- ROW KEY. This report has no natural key: one customer can pay twice against the same
-- quote on the same day for the same amount. n8n lands it keyed on the row's POSITION
-- plus a hash (`__row000123__abc`), so identical rows stay distinct. Nothing here may
-- assume the key means anything beyond "this row, in this generation".
--
-- All generations kept (a view). API quota cost: ZERO.

with report as (
    select * from {{ source('smartmoving', 'report_payments') }}
),

instances as (
    select instance_id, crm_timezone from {{ ref('dim_instance') }}
),

typed as (
    select
        r.source_instance_id,
        r.entity_id,
        r.report_generated_at,
        r.row_key,
        r._ingested_at,
        r._source_email,

        nullif(trim(r.row_data ->> 'Quote'), '')            as quote_number,
        nullif(trim(r.row_data ->> 'Job'), '')              as job_number,
        nullif(trim(r.row_data ->> 'Storage Account'), '')  as storage_account_number,

        nullif(trim(r.row_data ->> 'Customer Name'), '')    as customer_name,
        nullif(trim(r.row_data ->> 'Branch'), '')           as branch_name,
        nullif(trim(r.row_data ->> 'Type'), '')             as payment_method,
        nullif(trim(r.row_data ->> 'Payment Category'), '') as payment_category,
        nullif(trim(r.row_data ->> 'Custom Payment Description'), '') as payment_description,
        nullif(trim(r.row_data ->> 'Check / CC #'), '')     as instrument_reference,
        nullif(trim(r.row_data ->> 'CC Conf Code'), '')     as cc_confirmation_code,
        nullif(trim(r.row_data ->> 'Terminal Id'), '')      as terminal_id,
        nullif(trim(r.row_data ->> 'Merchant Ref'), '')     as merchant_reference,

        {{ rpt_date("r.row_data ->> 'Date'") }}             as payment_date_local,
        {{ rpt_num("r.row_data ->> 'Amount'") }}            as payment_amount,
        {{ rpt_num("r.row_data ->> 'CC Fee'") }}            as cc_fee,

        i.crm_timezone,
        r.row_data
    from report r
    left join instances i on i.instance_id = r.source_instance_id
)

select
    source_instance_id || ':' || row_key || ':'
        || to_char(report_generated_at, 'YYYYMMDDHH24MISS') as report_row_key,
    source_instance_id,
    entity_id,
    report_generated_at,
    row_key,

    -- WHAT THIS PAYMENT IS AGAINST. Checked in the order the data supports: a row with
    -- a Quote is an opportunity payment even if it also names a job, because the quote
    -- is the higher-level identity. Anything with none of the three would surface as
    -- 'unattached' rather than being dropped - there are none today, and if that ever
    -- changes it must be visible, not silent.
    case
        when quote_number           is not null then 'opportunity'
        when job_number             is not null then 'job'
        when storage_account_number is not null then 'storage_account'
        else 'unattached'
    end                                                     as payment_target,

    quote_number,
    job_number,
    storage_account_number,

    customer_name,
    branch_name,
    payment_date_local,
    payment_amount,
    cc_fee,
    payment_method,
    payment_category,
    payment_description,
    instrument_reference,
    cc_confirmation_code,
    terminal_id,
    merchant_reference,

    crm_timezone,
    _ingested_at,
    _source_email,
    row_data
from typed
