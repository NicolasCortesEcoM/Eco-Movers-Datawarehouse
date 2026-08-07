{#
  Normalise a text value for joining. Apply to BOTH sides of every status,
  referral-source and person-name join.

  Why this exists: the same business value arrives spelled several ways.
    - /api/leads/statuses returns "Booked " with a trailing space
    - dim_status_map keys read "Lost follow up 3 no response"
    - the reports emit "Follow up 3 - No Response"
  Lowercasing, collapsing every run of non-alphanumerics to a single space and
  trimming makes those the same key without editing the seeds (CLAUDE.md:
  preserve the business rules encoded in the CSVs).
#}
{% macro norm_text(col) -%}
    nullif(trim(regexp_replace(lower(coalesce({{ col }}, '')), '[^a-z0-9]+', ' ', 'g')), '')
{%- endmacro %}
