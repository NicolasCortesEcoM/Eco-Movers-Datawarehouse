{#
  Today's business date in a given timezone.

  `tz_expr` is a SQL expression, not a literal string - pass a column
  (b.timezone) or a quoted literal ("'America/Los_Angeles'"). Callers should pass
  a column resolved from core.branches so no model hardcodes a zone.

  Note: `serviceDate` values are already local business dates and must never be
  timezone-converted (smartmoving_sync_strategy.md 10.2). This macro is for
  deriving "today", not for shifting stored dates.
#}
{% macro entity_today(tz_expr) -%}
    (now() at time zone {{ tz_expr }})::date
{%- endmacro %}
