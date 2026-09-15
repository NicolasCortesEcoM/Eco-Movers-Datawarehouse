-- core.opportunities - the canonical opportunity.
-- Grain: one row per (source_instance_id, external_opportunity_id).
--
-- Every field is resolved independently by pick_latest: among the sources that
-- actually reported a value for that field, the most recently observed one wins.
-- See dbt/macros/pick_latest.sql for why this is per-field and not per-row.
--
-- LEADS ARE OPPORTUNITIES. This header used to say the opposite - "there is no
-- lead->opportunity map, /api/leads does not return an opportunityId" - and that
-- premise was simply wrong. The lead's own `id` IS the opportunity GUID: 23,717 of
-- 36,895 lead ids are byte-identical to an existing external_opportunity_id, and six
-- lead ids that were NOT in this table were put to GET /api/opportunities/{id} on
-- 2026-09-09 and all six came back 200 with the same id echoed. See the `api_leads`
-- arm in int_opportunity_observations for the full evidence.
--
-- The cost of believing otherwise was 13,196 missing opportunities - overwhelmingly
-- bad leads and leads still in progress, because every API opportunity path reaches
-- an opportunity through its JOBS and those never had one. They were not merely
-- absent: they were absent from the DENOMINATOR, so every conversion rate in the
-- sales marts was overstated.
--
-- No fuzzy matching is involved and none is needed. The join is on the identifier
-- SmartMoving itself issued.
--
-- Note the lost-leads REPORT keys on Quote #, so despite its name it enriches
-- opportunities, not leads - do not "fix" that.
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
lds as (select * from latest where source = 'api_leads'),
rpt as (select * from latest where source = 'report_lead_status'),
bkd as (select * from latest where source = 'report_booked_opps'),

-- SERVICE DATE INHERITED FROM THE OPPORTUNITY'S OWN JOBS - fallback only.
--
-- In SmartMoving the service date does not live on the opportunity, it lives on the
-- JOB. The customers sweep reaches 13,157 opportunities and reports a service date
-- for none of them, while 13,157 of those same 13,157 have a job that does carry
-- one. The date was in the warehouse the whole time; the opportunity simply never
-- looked at its own jobs, which is why `Closed` sat at 22% instead of ~100%.
--
-- MIN, not max: when several jobs exist this is the date work STARTED. It is only
-- ever used when the Lead Status report has nothing to say, so it never competes
-- with the CRM's own calculation.
job_service_date as (
    select
        j.source_instance_id || ':' || j.external_opportunity_id as opportunity_key,
        min(j.service_date) as service_date
    from {{ ref('int_job_latest_by_source') }} j
    where j.external_opportunity_id is not null
      and j.service_date is not null
    group by 1
),

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

-- Cancellation Details fields that no other source has. Same reasoning as
-- bkd_extra: one source, one winner per opportunity, no resolution to do.
-- ⚠️ The report window starts 2026-01-02, so cancelled_date is null for the ~4,850
-- cancellations older than that. A null date is NOT "not cancelled" - is_cancelled
-- comes from the status integer and covers all history.
cxl as (
    select * from {{ ref('int_report_cancellation_latest') }}
),

-- THE MARKETING CHANNEL of each opportunity, from the dim_referral_source seed.
--
-- Seeded, documented and tested since the start, and read by nothing until now. It
-- resolves 99.1% of in-scope opportunities that carry a referral source, and 90% of
-- them get a channel_group - far better than the seed's own fill rate suggests,
-- because the 41 rows that carry a channel are the high-volume sources.
--
-- DISTINCT ON is load-bearing. The seed intentionally holds several raw spellings of
-- one source so every CRM value resolves ("FMC Yesler Towers" and "FMC- Yesler
-- Towers"), and norm_text collapses them - two pairs collide today. Without the
-- dedupe this join fans out and silently duplicates opportunities, which would
-- inflate every count built on them. tests/assert_referral_source_collisions_agree.sql
-- fails if colliding rows ever stop agreeing on what they mean.
referral as (
    select distinct on ({{ norm_text('referral_source_raw') }})
        {{ norm_text('referral_source_raw') }} as referral_key,
        -- The campaign LABEL. When the seed has no cleaned name, fall back to the
        -- seed's own canonical raw string - NOT to each opportunity's raw string.
        -- Found 2026-09-15: the CRM holds both "PNW Google Ads " (trailing space,
        -- 179 leads) and "PNW Google Ads" (124). Both normalise onto this one seed
        -- row, but with source_clean blank the label used to come from the raw
        -- value, so one source showed as two campaigns and ad spend mapped onto
        -- only one of them. Five sources had the same split.
        coalesce(nullif(trim(source_clean), ''),
                 trim(referral_source_raw))    as referral_source_clean,
        -- The marketing FAMILY the source rolls up to: `Google Ads Snohomish` and
        -- `Google Ads King` are both `Google Ads`. Two levels are needed because both
        -- questions are real - "how is the Snohomish campaign doing" and "how is
        -- Google Ads doing" - and a single column can only answer one of them.
        -- referral_source_clean stays the individual campaign; this is the roll-up.
        nullif(trim(campaign_group), '')       as referral_campaign_group,
        nullif(trim(channel_group), '')        as referral_channel_group,
        nullif(trim(platform), '')             as referral_platform,
        -- Already boolean: dbt's seed type inference turns the CSV's TRUE/FALSE into
        -- a real boolean, so this must NOT be treated as text. NULL stays NULL - "we
        -- do not know" and "not paid" are different answers, and a marketing ROI
        -- denominator must not conflate them.
        is_paid                                as referral_is_paid
    from {{ ref('dim_referral_source') }}
    order by 1, referral_source_raw
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
        --
        -- `api_leads` is the fourth, and it is the same enum: dim_opportunity_status
        -- resolves 0/1/30/50 identically for a lead and an opportunity. It is listed
        -- last so a tie goes to the opportunity endpoints, and it cannot go stale in
        -- a damaging direction: /api/leads stops returning a lead the moment it
        -- converts, so it can never overwrite Booked with an older In Progress.
        {{ pick_latest([
            ("enr.status_code", "enr.observed_at"),
            ("whk.status_code", "whk.observed_at"),
            ("swp.status_code", "swp.observed_at"),
            ("lds.status_code", "lds.observed_at")
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
        -- THE ONE FIELD THAT IS NOT A FRESHNESS RACE, deliberately.
        --
        -- Everything else here asks "who spoke most recently?". Service date asks
        -- "who is most authoritative?", in a fixed order:
        --
        --   1. The Lead Status report. The CRM computes this itself - when an
        --      opportunity has several jobs it picks the one it considers the real
        --      move date, by logic we do not have and should not reinvent.
        --   2. The API's opportunity-level date.
        --   3. The earliest date among the opportunity's own jobs.
        --
        -- coalesce, not pick_latest, because a newer source must NOT overrule the
        -- CRM's own answer just by being newer.
        --   4. The Lost Leads report's `Move Date`, LAST on purpose: for a lost
        --      lead that is the date the customer was planning on, not a booked
        --      commitment. It is better than nothing and worse than anything above.
        coalesce(
            rpt.service_date,
            enr.service_date,
            jsd.service_date,
            lost.service_date
        )                                                   as service_date,

        -- Where the date above actually came from. Without this the fallback is
        -- invisible: a job-inherited date and a CRM-calculated one look identical
        -- in the column, and only one of them is authoritative.
        case
            when rpt.service_date is not null then 'lead_status_report'
            when enr.service_date is not null then 'api_opportunity'
            when jsd.service_date is not null then 'inherited_from_job'
            when lost.service_date is not null then 'lost_leads_report'
        end                                                 as service_date_source,

        -- WHY a deal was lost, and when. Single-source fields, so they are joined
        -- straight in rather than routed through the observation layer - see
        -- int_report_lost_leads_latest for the reasoning.
        lost.lost_reason                                    as lost_reason,
        lost.lost_date                                      as lost_date,
        -- Minutes between the lead arriving and a first reply. Only populated for
        -- lost records: this report is the only source that carries it.
        lost.time_to_first_contact_minutes                  as time_to_first_contact_minutes,
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
            ("swp.customer_name", "swp.observed_at"),
            ("lds.customer_name", "lds.observed_at")
        ]) }}                                               as customer_name,
        {{ pick_latest([
            ("bkd.customer_email", "bkd.observed_at"),
            ("enr.customer_email", "enr.observed_at"),
            ("swp.customer_email", "swp.observed_at"),
            ("lds.customer_email", "lds.observed_at")
        ]) }}                                               as customer_email,
        {{ pick_latest([
            ("bkd.customer_phone", "bkd.observed_at"),
            ("enr.customer_phone", "enr.observed_at"),
            ("swp.customer_phone", "swp.observed_at"),
            ("lds.customer_phone", "lds.observed_at")
        ]) }}                                               as customer_phone,
        {{ pick_latest([("swp.customer_address", "swp.observed_at")]) }}
                                                            as customer_address,

        {{ pick_latest([
            ("enr.branch_name", "enr.observed_at"),
            ("rpt.branch_name", "rpt.observed_at"),
            ("ajo.branch_name",  "ajo.observed_at"),
            ("lds.branch_name",  "lds.observed_at")
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
            ("ajo.referral_source",  "ajo.observed_at"),
            ("lds.referral_source",  "lds.observed_at")
        ]) }}                                                              as referral_source,
        {{ pick_latest([("enr.affiliate_name", "enr.observed_at")]) }}      as affiliate_name,
        {{ pick_latest([("enr.tariff_name", "enr.observed_at")]) }}         as tariff_name,
        {{ pick_latest([
            ("enr.move_size_name", "enr.observed_at"),
            ("lds.move_size_name", "lds.observed_at")
        ]) }}                                                              as move_size_name,
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
            ("ajo.sales_person",        "ajo.observed_at"),
            ("lds.sales_assignee_name", "lds.observed_at")
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
        -- Two sources, so this one IS a freshness race. The API carries a reason on
        -- 219 of 6,331 cancelled opportunities; the Cancellation Details report
        -- carries one on 1,476, in a clean seven-value vocabulary. Ranked by recency
        -- so a fresher API answer still wins where an opportunity has both.
        {{ pick_latest([
            ("enr.cancellation_reason", "enr.observed_at"),
            ("cxl.cancellation_reason", "cxl.observed_at")
        ]) }}                                               as cancellation_reason,
        -- coalesce, not pick_latest, and the API first. A creation instant is an
        -- immutable fact, so "newest observation wins" is the wrong rule for it - a
        -- report that arrives daily would outrank the API's own answer every day
        -- purely by being newer. The two agree to the minute anyway; the ordering is
        -- about which source is authoritative, not which is fresher.
        coalesce(enr.created_at_utc, lds.created_at_utc, rpt.created_at_utc)
                                                    as created_at_utc,

        -- REALISED revenue, and the only column in the warehouse that carries it.
        -- Read straight off the Booked Opportunities report rather than through
        -- pick_latest, because there is exactly one source: `estimated_final_total`
        -- is a quote. `total_actual_cost` on All Jobs is the SAME realised figure,
        -- at job grain - measured 2026-09-01, 2,552 of 2,554 single-job
        -- opportunities agree to the cent, correlation 1.0000. Both are kept
        -- because they differ in grain, not in meaning: this one is the only
        -- opportunity-level realised total, All Jobs is the only per-job breakdown.
        bkd_extra.invoiced_amount                           as invoiced_amount,
        bkd_extra.booked_date_local                         as booked_date_local,
        cxl.cancelled_date                                  as cancelled_date_local,
        cxl.cancelled_amount                                as cancelled_amount,

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
    left join lds on lds.opportunity_key = b.opportunity_key
    left join del on del.opportunity_key = b.opportunity_key
    left join rpt on rpt.opportunity_key = b.opportunity_key
    left join bkd on bkd.opportunity_key = b.opportunity_key
    left join bkd_extra on bkd_extra.opportunity_key = b.opportunity_key
    left join cxl       on cxl.opportunity_key       = b.opportunity_key
    left join agent_from_jobs ajo on ajo.opportunity_key = b.opportunity_key
    left join job_service_date jsd on jsd.opportunity_key = b.opportunity_key
    left join {{ ref('int_report_lost_leads_latest') }} lost
      on lost.opportunity_key = b.opportunity_key
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
    -- PRIOR-TENANT GUARD. The `ld` SmartMoving account was in use by a different
    -- business before 2025, and the 2026-09-07 sweep back to 2023 pulled its records
    -- in alongside ours - they are indistinguishable by key, because quote numbers run
    -- continuously across the handover. They are distinguishable by date, and by their
    -- shape: pre-2025 `ld` rows carry no branch, no sales agent and no lead date.
    --
    -- Flagged, never filtered out here. `core` keeps everything the sources returned;
    -- it is the KPI marts that exclude out-of-scope rows, so the exclusion is visible
    -- and reversible instead of being a WHERE clause nobody can see. The boundary per
    -- instance lives in dim_instance.data_valid_from.
    --
    -- coalesce(..., true): a record with no date at all is not PROVABLY prior-tenant,
    -- and dropping it on a null would quietly lose in-scope rows.
    coalesce(
        coalesce(r.service_date,
                 (r.created_at_utc at time zone coalesce(b.timezone, i.timezone))::date)
            >= i.data_valid_from::date,
        true
    )                                   as is_in_scope,

    -- THE LOST/CANCELLED SUBCATEGORY, which the status integer cannot express.
    --
    -- dim_status_map has been seeded, tested and documented since the beginning, and
    -- three separate comments in this repo asserted that the Lead Status report joined
    -- to it - stg_smartmoving__report_lead_status.sql, macros/norm_text.sql and
    -- sql/33_report_lead_status.sql all say so. None of them was true: the join was
    -- never written, and the subcategory never reached core. Measured 2026-09-08, it
    -- resolves 93.5% of in-scope opportunities that carry a pipeline_status.
    --
    -- It contributes the SUBCATEGORY ONLY. status_category and every is_* flag stay
    -- with dim_opportunity_status, because the platform integer is authoritative for
    -- the outcome and the report string is not - 185 rows read `Closed` while the API
    -- said Booked. Two vocabularies for one question is how they drift.
    rs.referral_source_clean,
    rs.referral_campaign_group,
    rs.referral_channel_group,
    rs.referral_platform,
    rs.referral_is_paid,

    sm.status_subcategory,

    -- What the REPORT thinks the category is, kept beside the authoritative one rather
    -- than merged into it. Where the two disagree, that disagreement is the signal.
    sm.status_category                                      as status_category_reported,

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
left join {{ ref('dim_status_map') }} sm
       on {{ norm_text('sm.status_raw') }} = {{ norm_text('r.pipeline_status') }}
left join referral rs
       on rs.referral_key = {{ norm_text('r.referral_source') }}
