-- core.payments - every payment the business has received, as the CRM reports it.
-- Grain: one row per (source_instance_id, transaction identity, duplicate ordinal) -
-- ACCUMULATIVE across every Payments generation ever landed, see
-- int_report_payments_all for the identity and the deduplication rule.
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
-- ACCUMULATIVE, NOT A SNAPSHOT (changed 2026-09-15). The Payments export is a rolling
-- 90-day window; this model used to take the newest generation whole, so a payment
-- vanished from core the day it aged out. Now every generation is unioned and
-- deduplicated by transaction identity, so history from 2023 (local) / 2025 (ld) is
-- here and nothing ages out. Refunds are the negative rows. A payment edited or
-- voided inside the newest window is dropped (the newest export is the CRM's truth
-- there); see `is_current` in the int model.
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
    p.dup_seq,
    p.first_observed_at,
    p.last_observed_at,
    p.is_in_newest_generation,
    p.cc_fee,
    p.payment_method,
    p.payment_category,
    p.payment_description,
    p.cc_confirmation_code,
    p.merchant_reference,

    p.observed_at                                       as synced_at

from {{ ref('int_report_payments_all') }} p
left join {{ ref('int_opportunity_quote_crosswalk') }} x
  on  x.source_instance_id = p.source_instance_id
  and x.quote_number       = p.quote_number
-- Superseded rows (edited/voided inside the newest window) stay in the int model only.
where p.is_current
