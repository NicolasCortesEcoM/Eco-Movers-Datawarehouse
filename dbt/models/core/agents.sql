-- core.agents - the canonical sales roster.
-- Grain: one row per source_agent_name (the string the CRM actually writes).
--
-- WHY TWO SEEDS AND NOT ONE. A person's ROLE does not depend on the line of
-- business - Graydon is a Sales Agent in local and in long distance alike. Putting
-- the role on the assignment rows would repeat it once per line, and the day
-- someone changes role you must remember to edit every one of their rows. Missing
-- one is silent and wrong.
--
--   dim_agent            -> one row per NAME. Identity, role, aliases.
--   dim_agent_assignment -> one row per (canonical agent, line, period). Coverage.
--
-- So: change a role, edit one cell. Give someone a new line, add one row. The two
-- edits never collide, and nothing downstream is touched either way.
--
-- ALIASES. dim_agent maps the raw CRM string to a canonical name - `Grant K` and
-- `Grant Korzetz` are one person. Every downstream model joins on agent_name (the
-- canonical one), so adding a newly-observed spelling is a single row here and
-- every report that uses agents corrects itself on the next build.
--
-- An agent seen in the CRM but absent from dim_agent is NOT dropped: it comes
-- through with is_known = false so it can be found and added. Silently discarding
-- a salesperson's numbers is worse than showing them as unmapped.

with observed as (
    select distinct
        entity_id,
        sales_assignee_name as source_agent_name
    from {{ ref('opportunities') }}
    where nullif(trim(sales_assignee_name), '') is not null
),

roster as (
    select
        source_agent_name,
        agent_name,
        is_sales_agent,
        role,
        is_active,
        notes
    from {{ ref('dim_agent') }}
)

select
    o.entity_id,
    o.source_agent_name,
    -- Unknown names keep their own spelling as the canonical one so metrics still
    -- group them sensibly while they wait to be added to the seed.
    coalesce(r.agent_name, o.source_agent_name)     as agent_name,
    coalesce(r.is_sales_agent, true)                as is_sales_agent,
    r.role                                          as role,
    coalesce(r.is_active, true)                     as is_active,
    (r.source_agent_name is not null)               as is_known,
    r.notes                                         as notes
from observed o
left join roster r
  on {{ norm_text('r.source_agent_name') }} = {{ norm_text('o.source_agent_name') }}
