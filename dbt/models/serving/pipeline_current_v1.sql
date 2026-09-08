-- serving.pipeline_current_v1 - PUBLIC CONTRACT (Sales).
--
-- The live pipeline: one row per unresolved opportunity as of the last build.
-- Consumed via app_read, RLS-scoped by entity_id. Additive changes ship freely;
-- breaking changes require v2 with a 90-day overlap.
--
-- ⚠️ A SNAPSHOT OF NOW, NOT A TIME SERIES. It is rebuilt every run, so it answers
-- "what is in the pipeline today" and cannot answer "how did it move last week".
--
-- ⚠️ NEVER SUM `estimated_final_total` ACROSS THE WHOLE TABLE. Committed work
-- (`is_committed`) and speculative work (`is_speculative`) are different things and
-- the total of the two is the number that gets quoted in a meeting and then missed.
-- Report them separately.
--
-- Calibration, measured 2026-09-08: 628 unresolved opportunities, 485 future-dated,
-- and by service month it is 2026-09 ($678k committed), 2026-10 ($188k), then single
-- digits. The honest horizon is about two months. There is no probability-weighted
-- forecast column on purpose - weighting 162 open rows by a historical rate looks
-- like a forecast and behaves like a coin flip.

select
    opportunity_key,
    entity_id,
    source_instance_id,
    external_opportunity_id,
    quote_number,
    customer_name,
    branch_name,
    sales_assignee_name,
    line_of_business,
    referral_channel_group,
    referral_is_paid,

    status_label,
    status_category,
    is_committed,
    is_speculative,

    service_date,
    service_month,
    days_until_service,
    created_date_local,
    age_days,

    estimated_final_total,
    synced_at
from {{ ref('fct_pipeline_current') }}
