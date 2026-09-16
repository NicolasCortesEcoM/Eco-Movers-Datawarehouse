-- marts.int_report_payments_all - EVERY payment any Payments generation has ever
-- listed, once. Grain: one row per (instance, transaction identity, duplicate ordinal).
--
-- WHY ACCUMULATIVE. The Payments export is scheduled as a ROLLING 90-DAY WINDOW: each
-- generation covers "today - 90 days .. today". The previous model
-- (int_report_payments_latest) took the newest generation whole, which meant a
-- payment LEFT core the day it aged out of the window - a financial table that forgot
-- money every night. Nicolas, 2026-09-15: report-fed tables are accumulative - union
-- every generation, deduplicate by content, never drop a row because a later export
-- stopped listing it. Raw already keeps every generation (plus the manual exports
-- loaded with scripts/load_report_export.py), so the history is all here.
--
-- HOW DEDUPLICATION WORKS. SmartMoving emits no payment id, so identity is the
-- TRANSACTION itself: instance, day, amount, what it is against (quote / job / storage
-- account), method, and the instrument (card last digits, confirmation code,
-- terminal, merchant reference). Descriptive fields that a user can edit later -
-- customer name, branch, category, description, the CC fee that is '' in some
-- exports and 0 in others - are NOT part of the identity; the newest generation's
-- values win for them, so an edit updates the row instead of duplicating it.
--
-- Two genuinely identical payments (same customer pays the same amount twice the
-- same day, same card) are real and must both survive. Within ONE generation they
-- are two rows; `dup_seq` numbers them 1, 2. Across generations the row (identity,
-- dup_seq) is then collapsed with distinct on, newest generation first - so the
-- multiplicity kept is the maximum any single generation showed, never the sum.
--
-- EDITED AND VOIDED PAYMENTS. No export says "this row was removed", but the newest
-- generation is the CRM's current truth for every day INSIDE its window. So a row
-- dated inside the newest window that the newest generation no longer lists was
-- edited or voided in the CRM (measured 2026-09-15: 20 local rows in 3 months, all
-- Cash/Check entries later re-keyed - e.g. two checks replaced by one card payment).
-- `is_current` = still listed, or older than the newest window (history the CRM can
-- no longer show). core.payments keeps only is_current rows; the superseded ones stay
-- here with `first_observed_at` / `last_observed_at` so the edit is traceable.
-- WHAT A NEGATIVE ROW IS (audited 2026-09-15 on 1,556 negatives). SmartMoving writes
-- refunds, bounced payments and voids all as negative amounts with no marker of any
-- kind - no category, no description. They separate by shape:
--   bounce   a negative that exactly offsets an earlier positive on the same target,
--            same method, Check / E-Check: an NSF return. All 32 E-Check negatives are
--            this; the customer usually pays again days later (often + a fee).
--   refund   every other negative: money returned to the customer. Partial refunds by
--            check, card refunds (135 of 1,400 card negatives offset a payment in
--            full - a cancelled deposit refunded whole, still a refund).
-- `transaction_kind` carries that; `is_full_reversal` is the raw fact behind it.
-- Net cash is always sum(payment_amount) - both rows of a bounce cancel out - but a
-- refund report must exclude bounces, which are collection failures, not returns.
-- API quota cost: ZERO.

{{ config(materialized='table') }}

with rows_ as materialized (
    select
        r.*,
        md5(concat_ws('|',
            r.source_instance_id,
            r.payment_date_local::text,
            r.payment_amount::text,
            coalesce(r.quote_number, ''),
            coalesce(r.job_number, ''),
            coalesce(r.storage_account_number, ''),
            coalesce(r.payment_method, ''),
            coalesce(r.instrument_reference, ''),
            coalesce(r.cc_confirmation_code, ''),
            coalesce(r.terminal_id, ''),
            coalesce(r.merchant_reference, '')
        ))                                                   as identity_hash,
        row_number() over (
            partition by r.source_instance_id, r.report_generated_at,
                r.payment_date_local, r.payment_amount,
                r.quote_number, r.job_number, r.storage_account_number,
                r.payment_method, r.instrument_reference, r.cc_confirmation_code,
                r.terminal_id, r.merchant_reference
            order by r.row_key
        )                                                    as dup_seq
    from {{ ref('stg_smartmoving__report_payments') }} r
    where r.payment_date_local is not null
),

-- Staging parses jsonb per row; read it ONCE (rows_) and derive everything else from
-- that. A second pass through the view joined on report_generated_at cost 28 minutes.
newest_generation as (
    select source_instance_id, max(report_generated_at) as report_generated_at
    from rows_
    group by 1
),

-- The newest generation's window: the CRM's current truth covers these days.
newest_window as (
    select r.source_instance_id, min(r.payment_date_local) as window_start
    from rows_ r
    join newest_generation g
      on g.source_instance_id = r.source_instance_id
     and g.report_generated_at = r.report_generated_at
    group by 1
),

bounds as (
    select source_instance_id, identity_hash, dup_seq,
           min(report_generated_at) as first_observed_at,
           max(report_generated_at) as last_observed_at
    from rows_
    group by 1, 2, 3
),

deduped as (
select distinct on (r.source_instance_id, r.identity_hash, r.dup_seq)
    r.source_instance_id || ':' || r.identity_hash || ':' || r.dup_seq   as payment_key,
    r.entity_id,
    r.source_instance_id,
    r.identity_hash,
    r.dup_seq,
    r.report_generated_at                                   as observed_at,
    b.first_observed_at,
    b.last_observed_at,
    (b.last_observed_at = g.report_generated_at)            as is_in_newest_generation,
    (b.last_observed_at = g.report_generated_at
     or r.payment_date_local < w.window_start)              as is_current,

    r.payment_target,
    r.quote_number,
    r.job_number,
    r.storage_account_number,

    r.customer_name,
    r.branch_name,
    r.payment_date_local,
    r.payment_amount,
    r.cc_fee,
    r.payment_method,
    r.payment_category,
    r.payment_description,
    r.instrument_reference,
    r.cc_confirmation_code,
    r.terminal_id,
    r.merchant_reference
from rows_ r
join bounds b
  on  b.source_instance_id = r.source_instance_id
  and b.identity_hash      = r.identity_hash
  and b.dup_seq            = r.dup_seq
join newest_generation g on g.source_instance_id = r.source_instance_id
join newest_window     w on w.source_instance_id = r.source_instance_id
order by r.source_instance_id, r.identity_hash, r.dup_seq, r.report_generated_at desc
),

-- A negative row that exactly offsets an earlier (or same-day) positive on the same
-- target with the same method, within 60 days. Each positive can be consumed once.
reversals as (
    select n.payment_key, p.payment_key as reversed_payment_key
    from deduped n
    join lateral (
        select p.payment_key
        from deduped p
        where p.source_instance_id = n.source_instance_id
          and p.payment_amount     = -n.payment_amount
          and p.payment_amount     > 0
          and coalesce(p.quote_number, '')           = coalesce(n.quote_number, '')
          and coalesce(p.storage_account_number, '') = coalesce(n.storage_account_number, '')
          and coalesce(p.payment_method, '')         = coalesce(n.payment_method, '')
          and p.payment_date_local between n.payment_date_local - 60 and n.payment_date_local
        order by p.payment_date_local desc
        limit 1
    ) p on true
    where n.payment_amount < 0
)

select
    d.*,
    (rv.payment_key is not null)                            as is_full_reversal,
    rv.reversed_payment_key,
    case
        when d.payment_amount > 0 then 'payment'
        when d.payment_amount = 0 then 'zero'
        when rv.payment_key is not null
         and d.payment_method in ('Check', 'E-Check')       then 'bounce'
        else                                                     'refund'
    end                                                     as transaction_kind
from deduped d
left join reversals rv on rv.payment_key = d.payment_key
