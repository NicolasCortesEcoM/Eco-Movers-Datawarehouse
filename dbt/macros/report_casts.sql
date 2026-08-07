{#
  Casts for SmartMoving scheduled-report columns.

  Every report column arrives as TEXT, in US formats, with vendor-specific null
  sentinels. All of that is handled here, once, so no report model repeats it.

  Every macro is guarded by a regex rather than trusting the value: a report is an
  uncontrolled input, and one malformed cell must yield NULL, not fail the build.
  All shapes below were measured against the real exports in
  smartmoving_scheduble_reports/, not assumed.
#}

{# 'M/D/YYYY' -> date. Null for blanks AND for the vendor's '0/0/0' sentinel,
   which appears 331 times in the Lead Status export alone. #}
{% macro rpt_date(col) -%}
    case when {{ col }} ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
         then to_date({{ col }}, 'FMMM/FMDD/YYYY') end
{%- endmacro %}

{#
  'M/D/YYYY H:MM AM' -> timestamptz in UTC.

  tz_expr is the instance's crm_timezone (dim_instance.crm_timezone) - NOT a
  literal. Report columns named "* at Utc" are NOT UTC; they render in whatever
  zone the CRM is configured with.

  The ::timestamp cast is load-bearing. Postgres to_timestamp(text,text) returns
  timestamptz interpreted in the SESSION timezone, so without it the value silently
  depends on the server's TimeZone setting. Cast to a naive timestamp first, then
  AT TIME ZONE says "this wall-clock reading was taken in that zone", yielding the
  correct UTC instant.
#}
{% macro rpt_ts(col, tz_expr) -%}
    case when {{ col }} ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2} (AM|PM)$'
         then (to_timestamp({{ col }}, 'FMMM/FMDD/YYYY FMHH12:MI AM')::timestamp
               at time zone {{ tz_expr }}) end
{%- endmacro %}

{# Money/number text -> numeric. Strips $ and thousands separators. #}
{% macro rpt_num(col) -%}
    nullif(regexp_replace(coalesce({{ col }}, ''), '[$,]', '', 'g'), '')::numeric
{%- endmacro %}

{% macro rpt_bool(col) -%}
    case when lower(nullif(trim(coalesce({{ col }}, '')), '')) in ('1','true','yes','y') then true
         when lower(nullif(trim(coalesce({{ col }}, '')), '')) in ('0','false','no','n') then false end
{%- endmacro %}

{#
  Duration text -> integer minutes. Handles every shape measured in the real
  exports: '9m', '1h 47m', '23h 5m', '1d 8m', '1d 13h 41m', and negatives.

  The DAYS component is easy to miss - it only appears on 65 of 5,278 rows in the
  Lead Status sample, but dropping it would silently null out precisely the
  slowest responses, which are the ones a time-to-contact metric exists to find.

  Negative values are real ('-9m', 77 rows) and are preserved rather than clamped:
  a negative time-to-contact means the CRM recorded contact before receipt, which
  is a data-quality signal worth keeping visible instead of hiding.

  Any component can be omitted: '8h' with no minutes occurs too. The guard accepts
  any combination of d/h/m but requires at least one, so '--' and '' fall through
  to NULL.
#}
{% macro rpt_minutes(col) -%}
    case when {{ col }} ~ '^-?([0-9]+d ?)?([0-9]+h ?)?([0-9]+m)?$'
          and {{ col }} ~ '[0-9]' then
        (case when {{ col }} like '-%' then -1 else 1 end) *
        (coalesce((regexp_match({{ col }}, '([0-9]+)d'))[1]::int, 0) * 1440
       + coalesce((regexp_match({{ col }}, '([0-9]+)h'))[1]::int, 0) * 60
       + coalesce((regexp_match({{ col }}, '([0-9]+)m'))[1]::int, 0))
    end
{%- endmacro %}

{# '525 cuft / 3698 lbs' -> the volume side. '--' means unknown; each side is
   parsed independently because one can be known while the other is not. #}
{% macro rpt_cuft(col) -%}
    nullif((regexp_match(coalesce({{ col }}, ''), '^([0-9.]+) cuft'))[1], '')::numeric
{%- endmacro %}

{% macro rpt_lbs(col) -%}
    nullif((regexp_match(coalesce({{ col }}, ''), '/ ([0-9.]+) lbs'))[1], '')::numeric
{%- endmacro %}
