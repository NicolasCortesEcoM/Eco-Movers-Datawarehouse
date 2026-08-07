"""Instance registry: which SmartMoving instances exist, which business entity
each belongs to, and its operating timezone.

MUST stay in sync with the dbt seed `SCRDLA - dim_instance.csv` at the repo root.
instance -  entity: this company splits one entity across two instances by line
of business; other companies will map one instance to one entity (decisions/0002).

NOTE on `timezone`: this is only a FALLBACK default. The authoritative timezone
for local-date derivation is `core.branches.timezone` (a branch sits in one zone;
an entity may span zones) - see CLAUDE.md and smartmoving_sync_strategy.md section 10.2.

NOTE on `crm_timezone`: the zone the SmartMoving instance itself is configured
with, and therefore the zone its scheduled-report exports render in - including
the columns the vendor names "* at Utc", which are NOT UTC. Distinct from
`timezone`: branches can operate in zones the CRM does not render in. Report
parsing must resolve this per instance and never assume Pacific.
"""

INSTANCES = {
    "ld": {
        "entity_id": "ecomovers",
        "entity_name": "EcoMovers",
        "timezone": "America/Los_Angeles",
        "crm_timezone": "America/Los_Angeles",
        "lob_hint": "long_distance",
        "api_key_env": "SMARTMOVING_API_KEY_LD",
    },
    "local": {
        "entity_id": "ecomovers",
        "entity_name": "EcoMovers",
        "timezone": "America/Los_Angeles",
        "crm_timezone": "America/Los_Angeles",
        "lob_hint": "local_commercial",
        "api_key_env": "SMARTMOVING_API_KEY_LOCAL",
    },
}
