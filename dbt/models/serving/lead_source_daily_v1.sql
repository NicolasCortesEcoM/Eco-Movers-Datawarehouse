-- serving.lead_source_daily_v1 - PUBLIC CONTRACT (Sales / Marketing).
--
-- Lead volume, quality and conversion per marketing channel, line of business and
-- lead-arrival day. Consumed via app_read, RLS-scoped by entity_id. Additive changes
-- ship freely; breaking changes require v2 with a 90-day overlap.
--
-- Same cohort grain and the same maturity caveat as sales_agent_daily_v1: a recent
-- cohort always looks strong because its leads have not had time to be lost. Read
-- `open_leads` beside any conversion figure.
--
-- `channel_group = '(unmapped)'` is a real bucket, not an error - it carries the CRM
-- referral sources that dim_referral_source does not yet classify, around 6,200
-- opportunities converting at 41%. Filtering it away removes a tenth of the funnel.
--
-- This is the table marketing spend attaches to when it arrives: cost per lead, CAC
-- and ROAS become joins at (lead_received_date, channel_group). `any_paid_source`
-- says whether a cost denominator should exist at all.

select
    source_day_key,
    entity_id,
    channel_group,
    referral_platform,
    any_paid_source,
    line_of_business,
    lead_received_date,

    leads_received,
    valid_leads,
    bad_leads,
    booked_leads,
    lost_leads,
    cancelled_leads,
    open_leads,
    conversion_pct,
    bad_lead_pct,

    invoiced_deals,
    avg_invoiced_deal_size,
    booked_estimated_value,
    invoiced_value,

    lost_to_competitor,
    lost_on_price,
    lost_no_contact,

    synced_at
from {{ ref('fct_lead_source_daily') }}
