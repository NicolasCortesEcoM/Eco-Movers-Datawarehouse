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

-- One narrow CTE per source.
--
-- A new source is NOT free here, whatever int_opportunity_observations' header
-- suggests: the union arm makes the data available, but a field only starts
-- resolving against it once that source appears as a branch in the pick_latest
-- call below. Add the arm and forget the branch and everything still builds,
-- every test still passes, and the new source contributes precisely nothing -
-- which is exactly what happened on the first attempt at the report arm.
enr as (select * from latest where source = 'api_enrichment'),
whk as (select * from latest where source = 'api_webhook'),
swp as (select * from latest where source = 'api_sweep'),
del as (select * from latest where source = 'api_deletion'),
rpt as (select * from latest where source = 'report_lead_status'),
bkd as (select * from latest where source = 'report_booked_opps'),

-- SALES ATTRIBUTION RECOVERED FROM THE JOB SIDE.
--
-- 9,530 opportunities reach core through the customers sweep alone, and the sweep
-- does not return a sales person. The reports do - Lead Status 98%, All Jobs 100% -
-- but both attach by Quote #, and these opportunities do not resolve in the quote
-- crosswalk. So the field was 25% populated in core while being ~100% populated at
-- every source. That is a plumbing gap, not missing data.
--
-- All Jobs identifies its rows by job GUID, and the API arms already know which
-- opportunity each job belongs to. Going job -> opportunity closes it without a
-- single API call.
--
-- Note this is a LAST RESORT in the pick_latest ordering below: a value that came
-- straight from the opportunity always beats one inferred through its jobs.
agent_from_jobs as (
    select distinct on (j.source_instance_id, j.external_opportunity_id)
        j.source_instance_id || ':' || j.external_opportunity_id as opportunity_key,
        aj.sales_person,
        aj.estimator_name,
        aj.move_coordinator_name,
        aj.branch_name,
        aj.referral_source,
        aj.observed_at
    from {{ ref('int_job_latest_by_source') }} j
    join {{ ref('int_report_all_jobs_latest') }} aj
      on aj.job_key = j.job_key
    where j.external_opportunity_id is not null
    order by j.source_instance_id, j.external_opportunity_id, aj.observed_at desc
),

-- Booked-report fields that no other source has, so they need no resolution -
-- newest generation per opportunity and done. Kept out of the observation layer
-- for the same reason as int_report_all_jobs_latest: pick_latest earns its
-- complexity only where sources can disagree.
bkd_extra as (
    select distinct on (x.external_opportunity_id, r.source_instance_id)
        r.source_instance_id || ':' || x.external_opportunity_id as opportunity_key,
        r.invoiced_amount,
        r.booked_date_local
    from {{ ref('stg_smartmoving__report_booked_opportunities') }} r
    join {{ ref('int_opportunity_quote_crosswalk') }} x
      on  x.source_instance_id = r.source_instance_id
      and x.quote_number       = r.quote_number
    order by x.external_opportunity_id, r.source_instance_id, r.report_generated_at desc
),

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
            ("swp.quote_number", "swp.observed_at"),
            ("rpt.quote_number", "rpt.observed_at")
        ]) }}                                               as quote_number,

        -- The authoritative outcome. All three API sources report the same coding
        -- (verified identical across 657 opportunities), so this is a freshness
        -- race, not a reconciliation.
        {{ pick_latest([
            ("enr.status_code", "enr.observed_at"),
            ("whk.status_code", "whk.observed_at"),
            ("swp.status_code", "swp.observed_at")
        ]) }}                                               as status_code,

        -- The report's Status string and the API's leadStatus share this column
        -- because they are the same namespace: a human-facing pipeline label that
        -- the platform int cannot express. The report additionally carries the
        -- lost/cancelled SUBCATEGORY ("Lost price too high"), which is the whole
        -- reason it is worth ranking above the API here when it is fresher.
        {{ pick_latest([
            ("enr.pipeline_status", "enr.observed_at"),
            ("rpt.pipeline_status", "rpt.observed_at"),
            ("bkd.pipeline_status", "bkd.observed_at")
        ]) }}                                               as pipeline_status,
        {{ pick_latest([
            ("enr.service_date", "enr.observed_at"),
            ("rpt.service_date", "rpt.observed_at")
        ]) }}
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
            ("bkd.customer_name", "bkd.observed_at"),
            ("enr.customer_name", "enr.observed_at"),
            ("swp.customer_name", "swp.observed_at")
        ]) }}                                               as customer_name,
        {{ pick_latest([
            ("bkd.customer_email", "bkd.observed_at"),
            ("enr.customer_email", "enr.observed_at"),
            ("swp.customer_email", "swp.observed_at")
        ]) }}                                               as customer_email,
        {{ pick_latest([
            ("bkd.customer_phone", "bkd.observed_at"),
            ("enr.customer_phone", "enr.observed_at"),
            ("swp.customer_phone", "swp.observed_at")
        ]) }}                                               as customer_phone,
        {{ pick_latest([("swp.customer_address", "swp.observed_at")]) }}
                                                            as customer_address,

        {{ pick_latest([
            ("enr.branch_name", "enr.observed_at"),
            ("rpt.branch_name", "rpt.observed_at"),
            ("ajo.branch_name",  "ajo.observed_at")
        ]) }}                                                              as branch_name,
        {{ pick_latest([("enr.estimated_subtotal", "enr.observed_at")]) }}  as estimated_subtotal,
        {{ pick_latest([("enr.estimated_tax", "enr.observed_at")]) }}       as estimated_tax,

        -- The report contributes `Estimated Revenue` here, not to the subtotal.
        -- Every opportunity in the warehouse currently has zero tax, so the two are
        -- indistinguishable in the data and the mapping rests on the column name.
        -- Revisit when a taxed opportunity appears: if this is wrong, every
        -- report-sourced total is wrong by exactly the tax.
        {{ pick_latest([
            ("enr.estimated_final_total", "enr.observed_at"),
            ("rpt.estimated_final_total", "rpt.observed_at"),
            ("bkd.estimated_final_total", "bkd.observed_at")
        ]) }}                                                              as estimated_final_total,
        {{ pick_latest([
            ("enr.referral_source", "enr.observed_at"),
            ("rpt.referral_source", "rpt.observed_at"),
            ("ajo.referral_source",  "ajo.observed_at")
        ]) }}                                                              as referral_source,
        {{ pick_latest([("enr.affiliate_name", "enr.observed_at")]) }}      as affiliate_name,
        {{ pick_latest([("enr.tariff_name", "enr.observed_at")]) }}         as tariff_name,
        {{ pick_latest([("enr.move_size_name", "enr.observed_at")]) }}      as move_size_name,
        {{ pick_latest([
            ("enr.volume", "enr.observed_at"),
            ("rpt.volume", "rpt.observed_at")
        ]) }}                                                              as volume,
        {{ pick_latest([
            ("enr.weight", "enr.observed_at"),
            ("rpt.weight", "rpt.observed_at")
        ]) }}                                                              as weight,
        {{ pick_latest([
            ("enr.sales_assignee_name", "enr.observed_at"),
            ("rpt.sales_assignee_name", "rpt.observed_at"),
            ("ajo.sales_person",        "ajo.observed_at")
        ]) }}                                                              as sales_assignee_name,
        {{ pick_latest([
            ("ajo.estimator_name", "ajo.observed_at"),
            ("enr.estimator_name", "enr.observed_at"),
            ("rpt.estimator_name", "rpt.observed_at")
        ]) }}                                                              as estimator_name,
        {{ pick_latest([
            ("ajo.move_coordinator_name", "ajo.observed_at"),
            ("enr.move_coordinator_name", "enr.observed_at"),
            ("rpt.move_coordinator_name", "rpt.observed_at")
        ]) }}                                                              as move_coordinator_name,
        {{ pick_latest([("enr.cancellation_reason", "enr.observed_at")]) }} as cancellation_reason,
        {{ pick_latest([("enr.created_at_utc", "enr.observed_at")]) }}      as created_at_utc,

        -- REALISED revenue, and the only column in the warehouse that carries it.
        -- Read straight off the Booked Opportunities report rather than through
        -- pick_latest, because there is exactly one source: `estimated_final_total`
        -- is a quote, and All Jobs' `total_actual_cost` is cost, not revenue.
        -- Conflating any of the three would misstate the business.
        bkd_extra.invoiced_amount                           as invoiced_amount,
        bkd_extra.booked_date_local                         as booked_date_local,

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
            coalesce(del.observed_at, '-infinity'::timestamptz),
            coalesce(rpt.observed_at, '-infinity'::timestamptz),
            coalesce(bkd.observed_at, '-infinity'::timestamptz)
        )                                                   as synced_at
    from base b
    left join enr on enr.opportunity_key = b.opportunity_key
    left join whk on whk.opportunity_key = b.opportunity_key
    left join swp on swp.opportunity_key = b.opportunity_key
    left join del on del.opportunity_key = b.opportunity_key
    left join rpt on rpt.opportunity_key = b.opportunity_key
    left join bkd on bkd.opportunity_key = b.opportunity_key
    left join bkd_extra on bkd_extra.opportunity_key = b.opportunity_key
    left join agent_from_jobs ajo on ajo.opportunity_key = b.opportunity_key
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
