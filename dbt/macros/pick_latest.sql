{#
  Per-field "latest observation wins", skipping nulls.

  WHY NOT THE ROW-LEVEL VERSION. smartmoving_sync_strategy.md 12.3 sketches
  `select distinct on (entity_id, external_id) ... order by observed_at desc`,
  which picks one whole row from one source. That is wrong for this source mix and
  must not be built: our sources are COMPLEMENTARY, not competing. The API knows
  leadStatus, estimated totals and charge lines; the reports know invoiced_amount,
  move_coordinator, booked_date and structured addresses. A row-level winner nulls
  out everything the winner does not happen to know - the 06:00 report would wipe
  estimated_total off every opportunity.

  So each field is resolved independently: among the sources that actually
  reported a value for THIS field, take the most recently observed one.

  THE NULL-SKIP IS LOAD-BEARING, for a second reason. The sweep runs 5x a day and
  re-stamps its extraction timestamp even when nothing changed, so it would always
  out-timestamp a 3-day-old enrichment. That is correct for fields the sweep
  actually knows (a fresher sweep IS a fresher status reading) and harmless for the
  rest, because it contributes NULL there and is skipped.

  USAGE - a list of (value_expression, observed_at_expression) pairs, most
  authoritative first. List order is the tie-breaker when timestamps are equal:

      {{ pick_latest([
          ("enr.customer_name", "enr.observed_at"),
          ("swp.customer_name", "swp.observed_at")
      ]) }} as customer_name

  CALL-SITE RULE: every branch in one call must be the SAME SQL type. The VALUES
  list type-unifies its rows, so cast explicitly (e.g. `x::text`) when the sources
  disagree. Mixing types here is the one way to get a confusing error from this.
#}
{% macro pick_latest(candidates) -%}
(
    select pl.val
    from (values
        {%- for c in candidates %}
        ({{ c[0] }}, {{ c[1] }}, {{ loop.index }}){{ "," if not loop.last }}
        {%- endfor %}
    ) as pl(val, observed_at, pri)
    where pl.val is not null
      and pl.observed_at is not null
    order by pl.observed_at desc, pl.pri
    limit 1
)
{%- endmacro %}
