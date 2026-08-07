-- Enriched opportunities: GET /api/opportunities/{id} with all 10 Include* flags.
-- Grain: one row per (source_instance_id, external_opportunity_id) - verified unique.
-- Renamed and typed only; no business logic (ELT, CLAUDE.md rule 1).
--
-- Two status fields live here. They are NOT interchangeable:
--
--   status_code      THE authoritative business outcome. The int enum
--                    (0 NewLead, 1 LeadInProgress, 3 Opportunity, 4 Booked,
--                    10 Completed, 11 Closed, 20 Cancelled, 30 Lost, 50 BadLead).
--                    Labels and is_* flags come from the dim_opportunity_status
--                    seed. THIS is what every metric counts on.
--                    Verified identical to the sweep's status for all 657
--                    opportunities - the two endpoints do NOT differ.
--
--   pipeline_status  The CRM's free-form pipeline label ("CMET", "Follow Up",
--                    "Tentative Booking"). Useful context about where a rep has
--                    dragged the card, but NOT a metric: it is independent of the
--                    outcome, so a status_code=30 (Lost) row can still read
--                    'Booked' here. Never count on this field.
--
-- pipeline_status arrives with inconsistent trailing whitespace - both 'Booked'
-- and 'Booked ' occur - so it is trimmed once here at the boundary.

select
    source_instance_id || ':' || id             as opportunity_key,
    source_instance_id,
    entity_id,
    id                                          as external_opportunity_id,
    _dlt_id                                     as opportunity_dlt_id,

    -- bigint here, varchar on the sweep side: cast so the crosswalk can join.
    nullif(quote_number::text, '')              as quote_number,

    opportunity_type                            as opportunity_type_code,
    type                                        as service_type_id,
    case when service_date > 0
         then to_date(service_date::text, 'YYYYMMDD') end as service_date,
    status                                      as status_code,
    nullif(trim(lead_status), '')               as pipeline_status,

    volume,
    weight,
    volume_weight_calculation_mode              as volume_weight_calculation_mode_code,
    has_trip_info,
    trip_info__is_trip_info_applied             as is_trip_info_applied,
    allow_inventory_updates,

    nullif(referral_source, '')                 as referral_source,
    nullif(affiliate_id, '')                    as affiliate_id,
    nullif(affiliate_name, '')                  as affiliate_name,
    nullif(cancellation_reason, '')             as cancellation_reason,

    nullif(tariff__id, '')                      as tariff_id,
    nullif(tariff__name, '')                    as tariff_name,

    estimated_total__subtotal                   as estimated_subtotal,
    estimated_total__taxable_amount             as estimated_taxable_amount,
    estimated_total__tax                        as estimated_tax,
    estimated_total__final_total                as estimated_final_total,

    nullif(move_size__name, '')                 as move_size_name,
    nullif(move_size__description, '')          as move_size_description,
    move_size__volume                           as move_size_volume,

    nullif(branch__name, '')                    as branch_name,
    nullif(branch__phone_number, '')            as branch_phone,

    nullif(customer__id, '')                    as external_customer_id,
    nullif(customer__name, '')                  as customer_name,
    nullif(customer__email_address, '')         as customer_email,
    nullif(customer__phone_number, '')          as customer_phone,
    customer__phone_type                        as customer_phone_type_code,

    nullif(sales_assignee__id, '')              as sales_assignee_id,
    nullif(sales_assignee__name, '')            as sales_assignee_name,
    nullif(estimator__name, '')                 as estimator_name,
    nullif(estimator__mobile_number, '')        as estimator_mobile,
    nullif(estimator__branch_id, '')            as estimator_branch_id,
    nullif(estimator__title, '')                as estimator_title,
    nullif(move_coordinator__id, '')            as move_coordinator_id,
    nullif(move_coordinator__name, '')          as move_coordinator_name,

    created_at_utc,
    -- when this snapshot was taken; the observation timestamp the Phase 4
    -- observation layer orders on.
    _sm_snapshot_at                             as observed_at,
    _sm_extracted_at                            as synced_at
from {{ source('smartmoving', 'opportunities_enriched') }}
