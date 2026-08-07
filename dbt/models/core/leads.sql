-- core.leads - canonical leads. Grain: one row per (source_instance_id,
-- external_lead_id). Disposition is derived from the reason fields (reliable)
-- rather than the raw status int.
--
-- Local time resolves through core.branches.timezone (the authority CLAUDE.md
-- mandates), falling back to the instance default when a lead carries no branch
-- or names one we have not seen. No timezone is hardcoded here.

with leads as (
    select * from {{ ref('stg_smartmoving__leads') }}
),

branches as (
    select source_instance_id, branch_name, timezone
    from {{ ref('branches') }}
),

instances as (
    select instance_id, timezone from {{ ref('dim_instance') }}
),

-- Leads use the SAME status enum as opportunities (0 NewLead, 1 LeadInProgress,
-- 30 Lost, 50 BadLead are the values that occur on the leads endpoint), so one
-- seed serves both and "booked" means the same thing everywhere.
lead_status as (
    select * from {{ ref('dim_opportunity_status') }}
),

resolved as (
    select
        l.*,
        coalesce(b.timezone, i.timezone) as local_tz
    from leads l
    left join branches b
           on b.source_instance_id = l.source_instance_id
          and {{ norm_text('b.branch_name') }} = {{ norm_text('l.branch_name') }}
    left join instances i
           on i.instance_id = l.source_instance_id
),

with_status as (
    select r.*, s.status_name, s.status_category,
           s.is_booked, s.is_lost, s.is_bad_lead, s.is_open
    from resolved r
    left join lead_status s on s.status_code = r.lead_status_code
)

select
    lead_key,
    entity_id,
    source_instance_id,
    external_lead_id,
    customer_name,
    customer_phone,
    customer_email,
    referral_source,
    sales_person,
    branch_name,
    move_size,
    service_date,
    origin_city, origin_state, origin_zip,
    destination_city, destination_state, destination_zip,
    lead_status_code,
    coalesce(status_name, 'status_' || lead_status_code)    as lead_status_name,
    status_category                                         as lead_status_category,
    is_booked,
    is_lost,
    is_bad_lead,
    is_open,
    -- Kept alongside the seed label: the reason fields are finer-grained than the
    -- enum and are populated even when the code has not caught up.
    case
        when bad_lead_reason is not null then 'Bad Lead'
        when lost_reason is not null     then 'Lost'
        when lead_status_code = 1        then 'In Progress'
        when lead_status_code = 0        then 'New'
        else coalesce(status_name, 'status_' || lead_status_code)
    end                                                     as lead_disposition,
    lost_reason,
    bad_lead_reason,
    local_tz                                                as timezone,
    created_at_utc,
    (created_at_utc at time zone local_tz)                  as created_at_local,
    (created_at_utc at time zone local_tz)::date            as created_date_local,
    synced_at
from with_status
