-- The three cancellation objects must agree with core, or a manager comparing two
-- dashboards will find two different totals for the same month.
--   detail rows          = cancelled, in-scope, non-deleted opportunities in core
--   ZIP mart numerator   = the same count (cohort grain needs a lead date; the few
--                          without one are excluded on both sides)
--   reasons mart total   = detail rows that carry a cancellation date
with core_cx as (
    select count(*) n from {{ ref('opportunities') }} where is_cancelled and is_in_scope and not is_deleted
),
core_cx_dated as (
    select count(*) n from {{ ref('opportunities') }}
    where is_cancelled and is_in_scope and not is_deleted and created_date_local is not null
),
detail as (select count(*) n, count(cancelled_date) n_dated from {{ ref('int_cancellation_detail') }}),
zip as (select sum(cancellations) n from {{ ref('fct_cancellations_by_zip') }}),
reasons as (select sum(cancellations) n from {{ ref('fct_cancellation_reasons_monthly') }})
select c.n as core_cancelled, d.n as detail_rows, cd.n as core_with_lead_date, z.n as zip_cancellations,
       d.n_dated as detail_dated, r.n as reason_cancellations
from core_cx c, detail d, core_cx_dated cd, zip z, reasons r
where c.n <> d.n or cd.n <> z.n or d.n_dated <> r.n
