{#
  Use the +schema config as the LITERAL schema name (staging, core, marts, serving)
  instead of dbt's default `<target_schema>_<custom>` prefixing. This is what maps
  our models onto the layer schemas created by sql/00_bootstrap.sql.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
