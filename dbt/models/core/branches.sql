-- core.branches - canonical branches, and THE TIMEZONE AUTHORITY.
-- Grain: one row per (source_instance_id, external_branch_id).
--
-- CLAUDE.md mandates that branch-local time comes from core.branches.timezone as
-- an IANA name. Everything downstream that needs a local date resolves it here;
-- no model hardcodes a zone.
--
-- Three zones, deliberately distinct - conflating them is an off-by-one-day bug
-- waiting to happen:
--   timezone      - where the branch physically operates. Drives operational
--                   local dates (a job "today" is today at the branch).
--   crm_timezone  - what the SmartMoving instance is configured with, i.e. what
--                   the scheduled-report exports render in. The report columns
--                   the vendor names "* at Utc" are in THIS zone, not UTC.
--   UTC           - what we store. Always.
--
-- Resolution order for `timezone`: per-branch seed override, else the instance
-- default. Onboarding a company that spans zones is a seed edit, not a rewrite.

with branches as (
    select * from {{ ref('stg_smartmoving__branches') }}
),

instances as (
    select
        instance_id,
        timezone      as instance_timezone,
        crm_timezone  as instance_crm_timezone
    from {{ ref('dim_instance') }}
),

overrides as (
    select
        source_instance_id,
        branch_name,
        timezone as override_timezone
    from {{ ref('branch_timezone') }}
)

select
    b.source_instance_id || ':' || b.external_branch_id as branch_key,
    b.entity_id,
    b.source_instance_id,
    b.external_branch_id,
    b.branch_name,
    b.branch_phone,
    b.is_primary_branch,

    coalesce(o.override_timezone, i.instance_timezone)  as timezone,
    i.instance_crm_timezone                             as crm_timezone,
    (o.override_timezone is not null)                   as has_timezone_override,

    b.dispatch_address_full,
    b.dispatch_street,
    b.dispatch_city,
    b.dispatch_state,
    b.dispatch_zip,
    b.dispatch_lat,
    b.dispatch_lng,
    b.synced_at
from branches b
left join instances i
       on i.instance_id = b.source_instance_id
left join overrides o
       on o.source_instance_id = b.source_instance_id
      and {{ norm_text('o.branch_name') }} = {{ norm_text('b.branch_name') }}
