-- Every OBSERVATION any source has made about an opportunity, in one long table.
--
-- One row = "source S said this about opportunity O at time T". Sources disagree,
-- arrive out of order, and each knows a different subset of fields - so nothing is
-- resolved here. Resolution happens in core.opportunities via the pick_latest
-- macro, per field.
--
-- Grain: (opportunity_key, source, observed_at).
--
-- Columns are deliberately WIDE AND NULLABLE. A source contributes NULL for every
-- field it does not know, and pick_latest skips nulls - that is what lets a
-- report add invoiced_amount without erasing the API's estimated_total.
--
-- ADDING A SOURCE IS A `union all` ARM AND NOTHING ELSE. core.opportunities picks
-- up new arms automatically; the Phase 5 report arms (report_lead_status,
-- report_booked_opps, report_all_jobs) slot in here with no rewrite downstream.
-- That is the whole reason this layer exists.
--
-- source_priority breaks ties when two sources share an observed_at. Lower wins.

{#
  opportunity_deletions is created by dlt only when a deletion is first detected,
  so it may legitimately not exist yet. Guarding on the relation keeps the build
  green everywhere and lights the arm up automatically once the table appears,
  rather than making every environment wait for the first deleted opportunity.
#}
{% set deletions_rel = adapter.get_relation(
     database=target.database, schema='raw_smartmoving', identifier='opportunity_deletions') %}

with enrichment as (
    select
        opportunity_key,
        entity_id,
        source_instance_id,
        external_opportunity_id,
        'api_enrichment'                as source,
        1                               as source_priority,
        observed_at,

        status_code,
        quote_number::text              as quote_number,
        pipeline_status,
        service_date,
        opportunity_type_code,
        service_type_id,
        external_customer_id,
        customer_name,
        customer_email,
        customer_phone,
        -- the enriched payload has no customer address; only the sweep carries one
        null::text                      as customer_address,
        branch_name,
        estimated_subtotal::numeric     as estimated_subtotal,
        estimated_tax::numeric          as estimated_tax,
        estimated_final_total::numeric  as estimated_final_total,
        referral_source,
        affiliate_name,
        tariff_name,
        move_size_name,
        volume::numeric                 as volume,
        weight::numeric                 as weight,
        sales_assignee_name,
        estimator_name,
        move_coordinator_name,
        cancellation_reason,
        created_at_utc,
        false                           as is_deleted
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
),

-- Zero-API status feed. Knows the status int and nothing else, but knows it
-- within seconds of the change.
webhooks as (
    select
        source_instance_id || ':' || external_opportunity_id as opportunity_key,
        entity_id,
        source_instance_id,
        external_opportunity_id,
        'api_webhook'                   as source,
        2                               as source_priority,
        observed_at,

        opportunity_status_code         as status_code,
        null::text, null::text, null::date, null::bigint, null::bigint,
        null::text, null::text, null::text, null::text, null::text, null::text,
        null::numeric, null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::timestamptz,
        null::boolean
    from {{ ref('stg_smartmoving__webhook_opportunity_status') }}
),

-- The cheap sweep. Thin, but it runs 5x a day and covers opportunities the
-- detail call has not reached yet.
sweep as (
    select
        c.source_instance_id || ':' || o.external_opportunity_id as opportunity_key,
        c.entity_id,
        c.source_instance_id,
        o.external_opportunity_id,
        'api_sweep'                     as source,
        3                               as source_priority,
        c.synced_at                     as observed_at,

        o.opportunity_status_code       as status_code,
        o.quote_number::text            as quote_number,
        null::text                      as pipeline_status,
        null::date                      as service_date,
        null::bigint                    as opportunity_type_code,
        null::bigint                    as service_type_id,
        c.external_customer_id,
        c.customer_name,
        c.customer_email,
        c.customer_phone,
        c.customer_address,
        null::text                      as branch_name,
        null::numeric, null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::timestamptz,
        null::boolean
    from {{ ref('stg_smartmoving__opportunities') }} o
    join {{ ref('stg_smartmoving__customers') }} c
      on c.customer_dlt_id = o.customer_dlt_id
),

-- The Lead Status scheduled report. Zero API quota, and the only source that keeps
-- covering an opportunity after it leaves the sweep's service-date window - or that
-- never entered it, since the sweep only reaches opportunities that HAVE A JOB.
-- See crm_sync_contract.md for what each mechanism can and cannot reach.
--
-- Resolves through the quote crosswalk because the report carries no GUID. Rows that
-- do not resolve are NOT dropped silently - they surface in
-- marts.mart_unmatched_report_rows, per the identity-resolution rule.
--
-- WHAT THIS ARM DELIBERATELY DOES NOT CONTRIBUTE:
--
--   status_code. The report's Status is a different namespace from the platform int,
--   not a relabelling of it, and the live data proves it: 185 rows read `Closed` in
--   the report while the API says status_code 4 (Booked), and `Cancelled service no
--   longer needed` maps to BOTH 4 and 20 depending on the row. Deriving the int from
--   the string would manufacture agreement that does not exist. The string goes to
--   pipeline_status, which is where the lost/cancelled subcategory lives anyway - the
--   one thing the int genuinely cannot express.
--
--   Customer identity. The Lead Status export has 16 columns and none of them is a
--   customer name, email or phone.
--
--   is_deleted. A row's absence from a report means it fell outside the report's
--   date range, never that it was deleted.
report_lead_status as (
    select
        r.source_instance_id || ':' || x.external_opportunity_id as opportunity_key,
        r.entity_id,
        r.source_instance_id,
        x.external_opportunity_id,
        'report_lead_status'            as source,
        5                               as source_priority,
        r.report_generated_at           as observed_at,

        null::bigint                    as status_code,
        r.quote_number,
        r.status_raw                    as pipeline_status,
        r.service_date_local            as service_date,
        null::bigint                    as opportunity_type_code,
        null::bigint                    as service_type_id,
        null::text                      as external_customer_id,
        null::text                      as customer_name,
        null::text                      as customer_email,
        null::text                      as customer_phone,
        null::text                      as customer_address,
        r.branch_name,

        -- `Estimated Revenue` maps to the final total, not the subtotal.
        -- CAVEAT, and it is a real one: every opportunity in the warehouse today has
        -- estimated_tax = 0, so subtotal and final_total are identical and the data
        -- cannot distinguish them. The mapping rests on the column's name. Re-check
        -- the moment a taxed opportunity appears - if this is wrong, it is wrong by
        -- exactly the tax amount, on every report-sourced figure.
        null::numeric                   as estimated_subtotal,
        null::numeric                   as estimated_tax,
        r.estimated_revenue::numeric    as estimated_final_total,

        r.referral_source,
        null::text                      as affiliate_name,
        null::text                      as tariff_name,
        null::text                      as move_size_name,
        r.volume_cuft::numeric          as volume,
        r.weight_lbs::numeric           as weight,
        r.sales_person                  as sales_assignee_name,
        r.estimator_name,
        r.move_coordinator_name,
        null::text                      as cancellation_reason,
        null::timestamptz               as created_at_utc,
        null::boolean                   as is_deleted
    from {{ ref('stg_smartmoving__report_lead_status') }} r
    join {{ ref('int_opportunity_quote_crosswalk') }} x
      on  x.source_instance_id = r.source_instance_id
      and x.quote_number       = r.quote_number
),

-- The Booked Opportunities report. Contributes the customer contact and, uniquely,
-- what the customer was actually BILLED - see the staging model for why the other
-- 17 columns are deliberately not promoted.
--
-- Note it contributes `estimated_final_total` from `Estimated Amount`, same as Lead
-- Status does from `Estimated Revenue`. Both are quotes for the same opportunity, so
-- they genuinely can disagree, and pick_latest resolving them by recency is the
-- right answer rather than a problem.
report_booked as (
    select
        r.source_instance_id || ':' || x.external_opportunity_id as opportunity_key,
        r.entity_id,
        r.source_instance_id,
        x.external_opportunity_id,
        'report_booked_opps'            as source,
        4                               as source_priority,
        r.report_generated_at           as observed_at,

        null::bigint                    as status_code,
        r.quote_number,
        r.status_raw                    as pipeline_status,
        r.service_date_local            as service_date,
        null::bigint                    as opportunity_type_code,
        null::bigint                    as service_type_id,
        null::text                      as external_customer_id,
        r.customer_name,
        r.customer_email,
        r.customer_phone,
        null::text                      as customer_address,
        null::text                      as branch_name,
        null::numeric                   as estimated_subtotal,
        null::numeric                   as estimated_tax,
        r.estimated_amount::numeric     as estimated_final_total,
        null::text                      as referral_source,
        null::text                      as affiliate_name,
        null::text                      as tariff_name,
        null::text                      as move_size_name,
        null::numeric                   as volume,
        null::numeric                   as weight,
        null::text                      as sales_assignee_name,
        null::text                      as estimator_name,
        null::text                      as move_coordinator_name,
        null::text                      as cancellation_reason,
        null::timestamptz               as created_at_utc,
        null::boolean                   as is_deleted
    from {{ ref('stg_smartmoving__report_booked_opportunities') }} r
    join {{ ref('int_opportunity_quote_crosswalk') }} x
      on  x.source_instance_id = r.source_instance_id
      and x.quote_number       = r.quote_number
)

{% if deletions_rel %}
,
-- Soft deletes. Contributes is_deleted and nothing else, so a deletion marker can
-- never blank out an opportunity's other attributes.
deletions as (
    select
        source_instance_id || ':' || id as opportunity_key,
        entity_id,
        source_instance_id,
        id                              as external_opportunity_id,
        'api_deletion'                  as source,
        9                               as source_priority,
        _deleted_at                     as observed_at,

        null::bigint, null::text, null::text, null::date, null::bigint, null::bigint,
        null::text, null::text, null::text, null::text, null::text, null::text,
        null::numeric, null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::numeric, null::numeric,
        null::text, null::text, null::text, null::text,
        null::timestamptz,
        true                            as is_deleted
    from {{ source('smartmoving', 'opportunity_deletions') }}
)
{% endif %}

select * from enrichment
union all select * from webhooks
union all select * from sweep
union all select * from report_lead_status
union all select * from report_booked
{% if deletions_rel %}
union all select * from deletions
{% endif %}
