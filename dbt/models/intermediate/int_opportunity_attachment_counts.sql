-- Attachment counts per opportunity: documents, files, photos.
--
-- Counts, not rows, on purpose. job_documents alone is 9,393 rows against 765 jobs
-- (~12 per job) and carries only title/type/is_complete - no URL and no id, because
-- the free IncludeDocuments flag omits both. Nothing in the current scope needs a
-- document row; "does this opportunity have its paperwork" needs a number.
--
-- Actual URLs require GET /api/premium/opportunities/{id}/documents, one call per
-- opportunity. Out of scope.
--
-- Grain: one row per (source_instance_id, external_opportunity_id) that has at
-- least one attachment of any kind.

with opportunities as (
    select opportunity_dlt_id, source_instance_id, entity_id, external_opportunity_id
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
),

opp_documents as (
    select _dlt_parent_id as opportunity_dlt_id,
           count(*)                                as document_count,
           count(*) filter (where is_complete)     as document_complete_count
    from {{ source('smartmoving', 'opportunities_enriched__opportunity_documents') }}
    group by 1
),

opp_files as (
    select _dlt_parent_id as opportunity_dlt_id, count(*) as file_count
    from {{ source('smartmoving', 'opportunities_enriched__opportunity_files') }}
    group by 1
),

opp_photos as (
    select _dlt_parent_id as opportunity_dlt_id, count(*) as photo_count
    from {{ source('smartmoving', 'opportunities_enriched__photos') }}
    group by 1
),

-- job_documents hang off the JOB, so roll up to the opportunity via _dlt_root_id
-- (verified to equal the opportunity's _dlt_id).
job_documents as (
    select _dlt_root_id as opportunity_dlt_id,
           count(*)                            as job_document_count,
           count(*) filter (where is_complete) as job_document_complete_count
    from {{ source('smartmoving', 'opportunities_enriched__jobs__job_documents') }}
    group by 1
)

select
    o.source_instance_id,
    o.entity_id,
    o.external_opportunity_id,
    coalesce(d.document_count, 0)               as document_count,
    coalesce(d.document_complete_count, 0)      as document_complete_count,
    coalesce(jd.job_document_count, 0)          as job_document_count,
    coalesce(jd.job_document_complete_count, 0) as job_document_complete_count,
    coalesce(f.file_count, 0)                   as file_count,
    coalesce(p.photo_count, 0)                  as photo_count
from opportunities o
left join opp_documents d on d.opportunity_dlt_id = o.opportunity_dlt_id
left join opp_files     f on f.opportunity_dlt_id = o.opportunity_dlt_id
left join opp_photos    p on p.opportunity_dlt_id = o.opportunity_dlt_id
left join job_documents jd on jd.opportunity_dlt_id = o.opportunity_dlt_id
