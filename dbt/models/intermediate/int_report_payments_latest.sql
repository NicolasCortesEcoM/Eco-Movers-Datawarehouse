-- The newest Payments report generation, per instance. Every row of it.
--
-- WHY A WHOLE GENERATION AND NOT A PER-ROW WINNER. Every other report in this
-- warehouse keys on something stable - a Quote #, a Job Id - so the newest row per
-- KEY is well defined. The Payments export carries no such column: SmartMoving emits
-- no payment id, and two rows can be byte-identical because one customer can pay the
-- same amount against the same quote twice on the same day. Its row_key is therefore
-- the row's POSITION in the file (see the report_ingest workflow), which is stable
-- within a generation and meaningless across them - a payment shifts position as new
-- ones are added above it.
--
-- So the only sound collapse is "take the latest snapshot whole". The report is a
-- full export each time, not a delta, which makes that correct rather than merely
-- convenient. It also means this model cannot show a payment that has since dropped
-- out of the report window.
--
-- ⚠️ This is why raw_smartmoving.report_payments once held six copies of the same
-- generation: the row key used to include a content hash that was not stable across
-- re-ingests, so ON CONFLICT never matched. Fixed 2026-09-09; sql/38 holds the
-- cleanup. If a generation ever looks doubled again, that is the first thing to check.
--
-- API quota cost: ZERO.

{{ config(materialized='view') }}

with latest_generation as (
    select
        source_instance_id,
        max(report_generated_at) as report_generated_at
    from {{ ref('stg_smartmoving__report_payments') }}
    group by 1
)

select
    r.source_instance_id || ':' || r.row_key    as payment_key,
    r.entity_id,
    r.source_instance_id,
    r.report_generated_at                       as observed_at,

    -- What the payment is against: 'opportunity', 'job', 'storage_account' or
    -- 'unattached'. Classified in staging; see that model for the precedence rule.
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
    r.merchant_reference

from {{ ref('stg_smartmoving__report_payments') }} r
join latest_generation g
  on  g.source_instance_id  = r.source_instance_id
  and g.report_generated_at = r.report_generated_at
