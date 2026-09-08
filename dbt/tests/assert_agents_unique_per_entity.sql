-- core.agents is unique on the PAIR (entity_id, source_agent_name), not on the name.
--
-- agents.sql selects `distinct entity_id, sales_assignee_name`, so that pair is the
-- real grain. _core.yml used to test `unique` on source_agent_name alone, which
-- passed only because there is one entity today - it would have begun failing the
-- day a second company was onboarded, which is the worst possible moment to find out.
--
-- A singular test rather than dbt_utils.unique_combination_of_columns: this project
-- has no packages.yml on purpose, and one composite-key assertion is not worth taking
-- on a package dependency for.

select
    entity_id,
    source_agent_name,
    count(*) as n
from {{ ref('agents') }}
group by 1, 2
having count(*) > 1
