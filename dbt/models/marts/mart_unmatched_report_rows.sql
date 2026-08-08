-- Report rows that could not be attached to an API opportunity.
--
-- CLAUDE.md's identity-resolution rule: an unmatched record is surfaced for review,
-- never silently dropped. Without this model the report arm on
-- int_opportunity_observations would quietly discard everything that fails to
-- resolve, and nobody would know the coverage number.
--
-- MANY ROWS HERE ARE EXPECTED, and that is the point of reporting the reason rather
-- than the count. The Lead Status export is keyed on RECEIVED date and covers every
-- lead and opportunity in the period; the API sweep is keyed on SERVICE date and only
-- reaches opportunities that have a job at all. Bad leads never get a job, so they
-- resolve at ~6%. That gap is precisely the history the reports exist to supply at
-- zero quota. See crm_sync_contract.md section 3.
--
-- WHAT TO ACTUALLY WATCH: `no_quote_number`. The crosswalk cannot even be attempted
-- for those, and a rise means the export shape changed. And watch the resolution
-- rate for opportunities the API *should* know - a sudden drop there is the
-- signature of a wrong instance attribution, because quote numbers are unique only
-- within an instance and a misrouted email resolves against the wrong crosswalk.

{{ config(materialized='view') }}

with report as (
    select * from {{ ref('stg_smartmoving__report_lead_status') }}
),

latest_generation as (
    -- Only the newest generation per instance. Older generations are kept in
    -- staging for history, but re-reporting the same unmatched row once per
    -- generation would make this grow without ever telling anyone anything new.
    select source_instance_id, max(report_generated_at) as report_generated_at
    from report group by 1
),

unmatched as (
    select
        r.source_instance_id,
        r.entity_id,
        r.report_generated_at,
        r.row_key,
        r.quote_number,
        r.status_raw,
        r.branch_name,
        r.service_date_local,
        r.received_at_utc,
        r.estimated_revenue,
        case
            when r.quote_number is null then 'no_quote_number'
            else 'quote_not_in_api'
        end as unmatched_reason,
        r._source_email
    from report r
    join latest_generation g
      on  g.source_instance_id  = r.source_instance_id
      and g.report_generated_at = r.report_generated_at
    left join {{ ref('int_opportunity_quote_crosswalk') }} x
      on  x.source_instance_id = r.source_instance_id
      and x.quote_number       = r.quote_number
    where x.external_opportunity_id is null
)

select
    source_instance_id || ':' || row_key as unmatched_key,
    *,
    {{ dbt.current_timestamp() }} as synced_at
from unmatched
