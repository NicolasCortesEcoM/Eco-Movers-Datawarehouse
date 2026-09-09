-- int_opportunity_line is unique on (source_instance_id, external_opportunity_id).
--
-- The model now drives off core.opportunities instead of grouping job rows, so the
-- grain is inherited rather than produced by the GROUP BY that used to guarantee it.
-- A duplicate here would silently multiply every lead count in three marts, which is
-- exactly the class of bug that is invisible until someone reconciles a total.
--
-- A singular test rather than dbt_utils.unique_combination_of_columns: this project
-- has no packages.yml on purpose.

select
    source_instance_id,
    external_opportunity_id,
    count(*) as n
from {{ ref('int_opportunity_line') }}
group by 1, 2
having count(*) > 1
