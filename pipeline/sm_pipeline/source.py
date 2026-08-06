"""dlt source for SmartMoving raw extraction.

Every row is stamped with (source_instance_id, entity_id, _sm_extracted_at).
Primary keys are composite (source_instance_id, id) because SmartMoving GUIDs
are only unique within one instance. Raw mirrors the API shape - the wide
"everything about an opportunity" view is built later in dbt, never here.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import dlt

from .client import SmartMoving
from .instances import INSTANCES

# All 10 Include* flags of GET /api/opportunities/{id}. Per smartmoving_api_findings.md
# they do NOT cost extra quota - one call returns the maximal payload (estimates,
# origin/destination addresses, rates/charges, payments, trip info, documents, ...).
INCLUDE_ALL = {
    "IncludeTripInfo": True,
    "IncludePayments": True,
    "IncludeSurveys": True,
    "IncludeJobAddresses": True,
    "IncludeTasks": True,
    "IncludeFiles": True,
    "IncludePhotos": True,
    "IncludeDocuments": True,
    "IncludeCharges": True,
    "IncludeDispatchInfo": True,
}


def _opp_hash(opp: dict) -> str:
    """Change signature of an opportunity as seen in the cheap customers sweep:
    status + serviceDate + the set of (job id, job serviceDate). If this is
    unchanged since the last sweep, the opportunity needs no re-enrichment."""
    jobs = opp.get("jobs") or []
    job_sig = sorted([(j.get("id"), j.get("serviceDate")) for j in jobs])
    payload = [opp.get("status"), opp.get("serviceDate"), job_sig]
    return hashlib.sha1(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


# Reference lists: small, stable, refreshed as full snapshots (write_disposition=replace).
DIM_ENDPOINTS = [
    ("dim_branches", "/api/branches", {}),
    ("dim_users", "/api/users", {}),
    ("dim_referral_sources", "/api/referral-sources", {"includePrivate": True, "includeLeadProviders": True}),
    ("dim_service_types", "/api/service-types", {}),
    ("dim_move_sizes", "/api/move-sizes", {}),
    ("dim_tariffs", "/api/tariffs", {}),
    ("dim_lost_reasons", "/api/lost-reasons", {}),
    ("dim_bad_lead_reasons", "/api/bad-lead-reasons", {}),
    ("dim_cancellation_reasons", "/api/cancellation-reasons", {}),
    ("dim_arrival_windows", "/api/arrival-windows", {}),
]


def _ymd(d) -> int:
    return int(d.strftime("%Y%m%d"))


@dlt.source(root_key=True)
def smartmoving_source(
    instance_id: str,
    jobs: tuple[str, ...] = ("leads", "jobs_window", "dims"),
    leads_from: int | None = None,
    leads_to: int | None = None,
    days_ahead: int = 10,
    from_offset: int = -7,
    to_offset: int = 30,
    opp_ids: tuple[str, ...] | None = None,
    call_budget: int = 300,
    pace: float = 0.6,
):
    cfg = INSTANCES[instance_id]
    # pace: proactive throttle (~1.6 calls/s) to stay under SmartMoving's
    # short-window rate limit - a bare enrichment burst trips 429 (~120 calls/min).
    sm = SmartMoving(instance_id, budget=call_budget, pace=pace)
    # "today" is a business date in the entity's timezone, never UTC
    today_local = datetime.now(ZoneInfo(cfg["timezone"])).date()
    extracted_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

    def stamp(row: dict) -> dict:
        row["source_instance_id"] = instance_id
        row["entity_id"] = cfg["entity_id"]
        row["_sm_extracted_at"] = extracted_at
        return row

    def enrich_one(opp_id) -> dict | None:
        """Full opportunity payload (all Include* flags) for one id, stamped."""
        detail = sm.get("/api/opportunities/" + str(opp_id), **INCLUDE_ALL)
        if not detail:
            return None
        detail["_sm_snapshot_at"] = extracted_at
        return stamp(detail)

    # Targeted enrichment (webhook worker / --ids): enrich an explicit id list,
    # no sweep. Runs standalone - the sweep/leads/dims blocks are skipped because
    # run.py passes jobs=() with opp_ids set.
    if opp_ids:

        @dlt.resource(
            name="opportunities_enriched",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunities_enriched_by_id():
            for opp_id in opp_ids:
                row = enrich_one(opp_id)
                if row is not None:
                    yield row

        yield opportunities_enriched_by_id

    if "leads" in jobs:

        @dlt.resource(name="leads", primary_key=("source_instance_id", "id"), write_disposition="merge")
        def leads():
            for row in sm.paginate(
                "/api/leads",
                From=leads_from or _ymd(today_local),
                To=leads_to or _ymd(today_local),
                IncludeBad=True,
                IncludeLost=True,
            ):
                yield stamp(row)

        yield leads

    if "jobs_window" in jobs:

        @dlt.resource(
            name="customers_service_window",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def customers_service_window():
            for row in sm.paginate(
                "/api/customers",
                FromServiceDate=_ymd(today_local),
                ToServiceDate=_ymd(today_local + timedelta(days=days_ahead)),
                IncludeOpportunityInfo=True,
            ):
                row["_sweep_from"] = _ymd(today_local)
                row["_sweep_to"] = _ymd(today_local + timedelta(days=days_ahead))
                yield stamp(row)

        yield customers_service_window

    if "enrich" in jobs:
        # Diff-driven enrichment. The cheap customers sweep over the wide window
        # [today+from_offset, today+to_offset] is the change detector; only opps
        # whose signature changed since the last run get the expensive per-opp
        # call. Watermark lives in dlt source state (persisted in the destination,
        # so it works identically on duckdb and postgres). dlt extracts resources
        # in yield order, single-threaded by default, so `seen_ids` is fully
        # populated by the time the deletions resource runs (yielded last).
        sweep_from = _ymd(today_local + timedelta(days=from_offset))
        sweep_to = _ymd(today_local + timedelta(days=to_offset))

        @dlt.resource(
            name="customers_service_window",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def enrich_sweep():
            for row in sm.paginate(
                "/api/customers",
                FromServiceDate=sweep_from,
                ToServiceDate=sweep_to,
                IncludeOpportunityInfo=True,
            ):
                row["_sweep_from"] = sweep_from
                row["_sweep_to"] = sweep_to
                yield stamp(row)

        @dlt.transformer(
            data_from=enrich_sweep,
            name="opportunities_enriched",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunities_enriched(customer):
            st = dlt.current.source_state()
            hashes = st.setdefault("opp_hashes", {})
            seen = st.setdefault("seen_ids", [])
            for opp in customer.get("opportunities") or []:
                opp_id = opp.get("id")
                if not opp_id:
                    continue
                seen.append(opp_id)
                h = _opp_hash(opp)
                if hashes.get(opp_id) == h:
                    continue  # unchanged since last sweep - skip the API call
                hashes[opp_id] = h
                row = enrich_one(opp_id)
                if row is not None:
                    yield row

        @dlt.resource(
            name="opportunity_deletions",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunity_deletions():
            # Opps present last run but absent from this sweep = disappeared
            # (cancelled/deleted at source). Raw never physically deletes: we
            # record a marker; dbt treats a later enriched snapshot as "present
            # again". Advance the presence watermark to this run's seen set.
            st = dlt.current.source_state()
            prior = set(st.get("prior_ids", []))
            seen = set(st.get("seen_ids", []))
            for opp_id in sorted(prior - seen):
                yield stamp({"id": opp_id, "_deleted_at": extracted_at, "_delete_source": "sweep_disappearance"})
            st["prior_ids"] = sorted(seen)

        yield enrich_sweep
        yield opportunities_enriched
        yield opportunity_deletions

    if "dims" in jobs:
        # factory closure: dlt injects config into resource-function *arguments*
        # (an arg named `path` would resolve from the PATH env var), so the
        # endpoint must be captured by closure, never passed as a default arg.
        # merge (not replace): each instance loads separately and replace would
        # wipe the other instance's rows; rows removed at source keep existing
        # until a cleanup - acceptable for reference lists that rarely shrink.
        def _make_dim(dim_name: str, endpoint: str, extra_params: dict):
            @dlt.resource(
                name=dim_name,
                primary_key=("source_instance_id", "id"),
                write_disposition="merge",
            )
            def dim():
                for row in sm.paginate(endpoint, **extra_params):
                    yield stamp(row)

            return dim

        for name, path, extra in DIM_ENDPOINTS:
            yield _make_dim(name, path, extra)

        @dlt.resource(
            name="dim_lead_statuses",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def dim_lead_statuses():
            for row in sm.get("/api/leads/statuses"):
                yield stamp(row)

        yield dim_lead_statuses
