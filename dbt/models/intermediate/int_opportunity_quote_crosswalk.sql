-- (source_instance_id, quote_number) -> external_opportunity_id.
--
-- THE BRIDGE EVERY REPORT NEEDS. Only all-jobs.xlsx carries a GUID; the booked,
-- lost-leads, cancellation, payments and outstanding-balance reports all key on the
-- human-readable Quote #. Without this they cannot be attached to anything.
--
-- Built from the API side ONLY, deliberately - a report must resolve against what
-- the API says, never against another report.
--
-- The composite key is not optional. Quote numbers are unique only WITHIN an
-- instance, so a naked quote number would silently attach a `local` quote to an
-- `ld` opportunity. No collision exists in the current data (708/708 distinct on
-- the sweep side), but that is a property of today's data, not a guarantee.
--
-- Type hazard: quote_number is bigint on opportunities_enriched and varchar on the
-- sweep child table. Both sides are normalised to text upstream in staging; drop
-- that cast and this model silently returns nothing.

with enriched as (
    select
        source_instance_id,
        quote_number,
        external_opportunity_id,
        observed_at
    from {{ ref('stg_smartmoving__opportunities_enriched') }}
    where quote_number is not null
),

sweep as (
    select
        c.source_instance_id,
        o.quote_number,
        o.external_opportunity_id,
        c.synced_at as observed_at
    from {{ ref('stg_smartmoving__opportunities') }} o
    join {{ ref('stg_smartmoving__customers') }} c
      on c.customer_dlt_id = o.customer_dlt_id
    where o.quote_number is not null
),

unioned as (
    select *, 1 as source_priority from enriched   -- detail call wins ties
    union all
    select *, 2 as source_priority from sweep
)

select distinct on (source_instance_id, quote_number)
    source_instance_id || ':' || quote_number as quote_key,
    source_instance_id,
    quote_number,
    external_opportunity_id,
    observed_at as resolved_at
from unioned
order by source_instance_id, quote_number, observed_at desc, source_priority
