-- core.opportunities - the canonical opportunity.
-- Grain: one row per (source_instance_id, external_opportunity_id).
--
-- Every field is resolved independently by pick_latest: among the sources that
-- actually reported a value for that field, the most recently observed one wins.
-- See dbt/macros/pick_latest.sql for why this is per-field and not per-row.
--
-- SEPARATE FROM LEADS BY DESIGN. There is no join to core.leads and no
-- lead->opportunity map. /api/leads does not return an opportunityId, and the
-- fuzzy email/phone/branch/date match that sync strategy 10.1 sketches is
-- deliberately out of scope. Note the lost-leads REPORT keys on Quote #, so
-- despite its name it enriches opportunities, not leads - do not "fix" that.
--
-- Status: `status_code` (the int) is authoritative and drives every is_* flag via
-- the dim_opportunity_status seed. `pipeline_status` is the CRM's pipeline label -
-- kept as context, never counted on. See status_model.md.

with latest as (
    select * from {{ ref('int_opportunity_latest_by_source') }}
),

-- One narrow CTE per source. Adding a Phase 5 report source means adding a CTE
-- here and extra branches to the pick_latest calls below - core's shape does not
-- otherwise change.
enr as (select * from latest where source = 'api_enrichment'),
whk as (select * from latest where source = 'api_webhook'),
swp as (select * from latest where source = 'api_sweep'),
del as (select * from latest where source = 'api_deletion'),

base as (
    select distinct
        opportunity_key,
        entity_id,
        source_instance_id,
        external_opportunity_id
    from latest
),

resolved as (
    select
        b.opportunity_key,
        b.entity_id,
        b.source_instance_id,
        b.external_opportunity_id,

        {{ pick_latest([
            ("enr.quote_number", "enr.observed_at"),
            ("swp.quote_number", "swp.observed_at")
        ]) }}                                               as quote_number,

        -- The authoritative outcome. All three API sources report the same coding
        -- (verified identical across 657 opportunities), so this is a freshness
        -- race, not a reconciliation.
        {{ pick_latest([
            ("enr.status_code", "enr.observed_at"),
            ("whk.status_code", "whk.observed_at"),
            ("swp.status_code", "swp.observed_at")
        ]) }}                                               as status_code,

        {{ pick_latest([("enr.pipeline_status", "enr.observed_at")]) }}
                                                            as pipeline_status,
        {{ pick_latest([("enr.service_date", "enr.observed_at")]) }}
                                                            as service_date,
        {{ pick_latest([("enr.opportunity_type_code", "enr.observed_at")]) }}
                                                            as opportunity_type_code,
        {{ pick_latest([("enr.service_type_id", "enr.observed_at")]) }}
                                                            as service_type_id,

        {{ pick_latest([
            ("enr.external_customer_id", "enr.observed_at"),
            ("swp.external_customer_id", "swp.observed_at")
        ]) }}                                               as external_customer_id,
        {{ pick_latest([
            ("enr.customer_name", "enr.observed_at"),
            ("swp.customer_name", "swp.observed_at")
        ]) }}                                               as customer_name,
        {{ pick_latest([
            ("enr.customer_email", "enr.observed_at"),
            ("swp.customer_email", "swp.observed_at")
        ]) }}                                               as customer_email,
        {{ pick_latest([
            ("enr.customer_phone", "enr.observed_at"),
            ("swp.customer_phone", "swp.observed_at")
        ]) }}                                               as customer_phone,
        {{ pick_latest([("swp.customer_address", "swp.observed_at")]) }}
                                                            as customer_address,

        {{ pick_latest([("enr.branch_name", "enr.observed_at")]) }}         as branch_name,
        {{ pick_latest([("enr.estimated_subtotal", "enr.observed_at")]) }}  as estimated_subtotal,
        {{ pick_latest([("enr.estimated_tax", "enr.observed_at")]) }}       as estimated_tax,
        {{ pick_latest([("enr.estimated_final_total", "enr.observed_at")]) }} as estimated_final_total,
        {{ pick_latest([("enr.referral_source", "enr.observed_at")]) }}     as referral_source,
        {{ pick_latest([("enr.affiliate_name", "enr.observed_at")]) }}      as affiliate_name,
        {{ pick_latest([("enr.tariff_name", "enr.observed_at")]) }}         as tariff_name,
        {{ pick_latest([("enr.move_size_name", "enr.observed_at")]) }}      as move_size_name,
        {{ pick_latest([("enr.volume", "enr.observed_at")]) }}              as volume,
        {{ pick_latest([("enr.weight", "enr.observed_at")]) }}              as weight,
        {{ pick_latest([("enr.sales_assignee_name", "enr.observed_at")]) }} as sales_assignee_name,
        {{ pick_latest([("enr.estimator_name", "enr.observed_at")]) }}      as estimator_name,
        {{ pick_latest([("enr.move_coordinator_name", "enr.observed_at")]) }} as move_coordinator_name,
        {{ pick_latest([("enr.cancellation_reason", "enr.observed_at")]) }} as cancellation_reason,
        {{ pick_latest([("enr.created_at_utc", "enr.observed_at")]) }}      as created_at_utc,

        -- A deletion marker only counts if nothing newer has been observed; a
        -- reappearance therefore un-deletes the opportunity on its own.
        coalesce({{ pick_latest([
            ("del.is_deleted", "del.observed_at"),
            ("enr.is_deleted", "enr.observed_at")
        ]) }}, false)                                       as is_deleted,
        del.observed_at                                     as deleted_at,

        -- Freshness a consumer can trust: the newest moment ANY source spoke.
        greatest(
            coalesce(enr.observed_at, '-infinity'::timestamptz),
            coalesce(whk.observed_at, '-infinity'::timestamptz),
            coalesce(swp.observed_at, '-infinity'::timestamptz),
            coalesce(del.observed_at, '-infinity'::timestamptz)
        )                                                   as synced_at
    from base b
    left join enr on enr.opportunity_key = b.opportunity_key
    left join whk on whk.opportunity_key = b.opportunity_key
    left join swp on swp.opportunity_key = b.opportunity_key
    left join del on del.opportunity_key = b.opportunity_key
)

select
    r.*,
    coalesce(s.status_name, 'status_' || r.status_code)     as status_label,
    s.status_category,
    coalesce(s.is_booked,    false)                         as is_booked,
    coalesce(s.is_completed, false)                         as is_completed,
    coalesce(s.is_cancelled, false)                         as is_cancelled,
    coalesce(s.is_lost,      false)                         as is_lost,
    coalesce(s.is_bad_lead,  false)                         as is_bad_lead,
    coalesce(s.is_open,      false)                         as is_open,
    coalesce(s.is_valid_lead, true)                         as is_valid_lead,
    b.timezone,
    (r.created_at_utc at time zone coalesce(b.timezone, i.timezone))::date as created_date_local
from resolved r
left join {{ ref('dim_opportunity_status') }} s
       on s.status_code = r.status_code
left join {{ ref('branches') }} b
       on b.source_instance_id = r.source_instance_id
      and {{ norm_text('b.branch_name') }} = {{ norm_text('r.branch_name') }}
left join {{ ref('dim_instance') }} i
       on i.instance_id = r.source_instance_id
