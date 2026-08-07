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
{% if deletions_rel %}
union all select * from deletions
{% endif %}
