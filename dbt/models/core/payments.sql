-- core.payments - every payment the business has received, as the CRM reports it.
-- Grain: one row per (source_instance_id, row position in the newest Payments export).
--
-- ⚠️ NOT THE SAME THING AS core.opportunity_payments, AND BOTH ARE CORRECT.
--
--   core.opportunity_payments  Payments embedded in the enriched opportunity payload.
--                              Sourced from the API, so it only covers opportunities a
--                              detail call has actually reached - 1,965 rows. It has a
--                              real opportunity GUID and payment ordinal, and it is
--                              the right table when you are working from an
--                              opportunity outwards.
--
--   THIS MODEL                 The Payments scheduled report, whole. It covers every
--                              payment in the report window regardless of whether the
--                              opportunity was ever enriched, and it carries what the
--                              API payload does not: the payment DATE, the method, the
--                              card confirmation code, the terminal, and payments made
--                              against a JOB or a STORAGE ACCOUNT rather than an
--                              opportunity. It costs zero quota.
--
-- They are not merged, deliberately. There is no shared payment identifier to merge
-- ON - the API payload carries no payment id and the report carries no GUID - so any
-- union would either double count or invent a match. Two tables with clearly
-- different scopes beat one table with a fabricated key.
--
-- WHAT THIS CANNOT DO. It is a snapshot of the newest export, not an append-only
-- ledger: a payment that falls out of the report window disappears from here. Do not
-- use it as a financial system of record, and do not diff two builds of it to detect
-- refunds. It answers "what has been paid, against what, by what method, when".
--
-- The opportunity link resolves through the quote crosswalk like every other report.
-- Rows whose quote never resolves keep external_opportunity_id null rather than being
-- dropped: an unattached payment is money that exists and must stay visible.

{{ config(materialized='table') }}

select
    p.payment_key,
    p.entity_id,
    p.source_instance_id,

    p.payment_target,
    p.quote_number,
    -- Null where the quote has no GUID yet. The quote_backfill drain closes these
    -- over time; see crm_sync_contract.md section 2a.
    x.external_opportunity_id,
    p.job_number,
    p.storage_account_number,

    p.customer_name,
    p.branch_name,

    p.payment_date_local,
    p.payment_amount,
    p.cc_fee,
    p.payment_method,
    p.payment_category,
    p.payment_description,
    p.cc_confirmation_code,
    p.merchant_reference,

    p.observed_at                                       as synced_at

from {{ ref('int_report_payments_latest') }} p
left join {{ ref('int_opportunity_quote_crosswalk') }} x
  on  x.source_instance_id = p.source_instance_id
  and x.quote_number       = p.quote_number
