"""dlt source for SmartMoving raw extraction.

Every row is stamped with (source_instance_id, entity_id, _sm_extracted_at).
Primary keys are composite (source_instance_id, id) because SmartMoving GUIDs
are only unique within one instance. Raw mirrors the API shape - the wide
"everything about an opportunity" view is built later in dbt, never here.
"""

from __future__ import annotations

import hashlib
import json
import re
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


_ISO_DATE_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})")


def _opp_hash(opp: dict) -> str:
    """Signature of EVERYTHING the cheap /api/customers sweep exposes for one
    opportunity.

    Deliberately not a change signature for the opportunity as a whole: money
    (estimatedTotal), the custom leadStatus, charges, payments and addresses are
    invisible to the sweep and CANNOT be detected here at any cost. A re-quote or
    a CMET -> Booked transition produces an identical hash. Those are covered by
    (1) the staleness TTL below and (2) the report-driven fingerprint queue
    (marts.mart_enrichment_candidates). Hashing the whole sweep object rather
    than three hand-picked fields costs nothing and picks up any field
    SmartMoving adds to the sweep later."""
    body = {k: v for k, v in opp.items() if k != "jobs"}
    jobs = sorted((opp.get("jobs") or []), key=lambda j: str(j.get("id")))
    payload = {"o": body, "j": jobs}
    return hashlib.sha1(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


def _to_ymd(v) -> int | None:
    """Coerce a SmartMoving date to YYYYMMDD int. The API is inconsistent: the
    sweep returns jobs[].serviceDate as an ISO string ("2026-07-20") while the
    opportunity detail returns serviceDate as an int (20260720)."""
    if v is None:
        return None
    if isinstance(v, int):
        return v if v > 19000000 else None
    s = str(v).strip()
    if not s:
        return None
    if s.isdigit() and len(s) == 8:
        return int(s)
    m = _ISO_DATE_RE.match(s)
    return int(m.group(1) + m.group(2) + m.group(3)) if m else None


def _opp_service_span(opp: dict) -> tuple[int | None, int | None]:
    """(min, max) service date as YYYYMMDD across the opportunity and its jobs.

    The sweep filters on JOB service date, so this span is what determines
    whether a given sweep window could have seen this opportunity at all - which
    is what makes absence meaningful. Note the sweep's opportunity object often
    carries no serviceDate of its own; the jobs are the reliable source."""
    dates = [d for d in (_to_ymd(j.get("serviceDate")) for j in (opp.get("jobs") or [])) if d]
    own = _to_ymd(opp.get("serviceDate"))
    if own:
        dates.append(own)
    return (min(dates), max(dates)) if dates else (None, None)


def _migrate_opp_state(st, now_iso: str) -> dict:
    """One-time move from the old {opp_hashes, seen_ids, prior_ids} layout to a
    single per-opportunity record. `t` is seeded to now so the first run after the
    upgrade does not re-enrich the entire window at once; the cold TTL then
    spreads the real refresh out naturally."""
    opps = st.get("opps")
    if opps is not None:
        return opps
    opps = {oid: {"h": h, "t": now_iso} for oid, h in (st.get("opp_hashes") or {}).items()}
    st["opps"] = opps
    for legacy in ("opp_hashes", "seen_ids", "prior_ids"):
        st.pop(legacy, None)
    return opps


def _parse_iso(iso: str | None) -> datetime | None:
    if not iso:
        return None
    try:
        return datetime.fromisoformat(iso)
    except ValueError:
        return None


def _hours_since(iso: str | None, now: datetime) -> float | None:
    dt = _parse_iso(iso)
    return None if dt is None else (now - dt).total_seconds() / 3600.0


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
    hot_ttl_hours: float = 24.0,
    cold_ttl_hours: float = 336.0,
    refresh_stale_hours: float | None = None,
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

    def enrich_one(opp_id) -> tuple[dict | None, bool]:
        """Full opportunity payload (all Include* flags) for one id, stamped.

        Returns (row, missing). missing=True means the API answered 404 - the
        opportunity is gone at source and the caller records a soft-delete marker
        instead of letting the exception kill the run."""
        detail = sm.get("/api/opportunities/" + str(opp_id), allow_missing=True, **INCLUDE_ALL)
        if detail is None:
            return None, True
        if not detail:
            return None, False
        detail["_sm_snapshot_at"] = extracted_at
        return stamp(detail), False

    # Targeted enrichment (webhook worker / --ids): enrich an explicit id list,
    # no sweep. Runs standalone - the sweep/leads/dims blocks are skipped because
    # run.py passes jobs=() with opp_ids set.
    if opp_ids:
        # 404s here are expected and normal: an `opportunity-deleted` webhook feeds
        # the id straight back to the detail endpoint. Record a soft-delete marker
        # rather than failing the batch and losing every other id in it.
        now_iso_ids = datetime.now(timezone.utc).isoformat(timespec="seconds")

        @dlt.resource(
            name="opportunities_enriched",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunities_enriched_by_id():
            st = dlt.current.source_state()
            opps = _migrate_opp_state(st, now_iso_ids)
            for opp_id in opp_ids:
                opp_id = str(opp_id)
                rec = opps.setdefault(opp_id, {})
                row, missing = enrich_one(opp_id)
                if missing:
                    rec["gone"], rec["gp"], rec["g404"] = now_iso_ids, True, True
                    continue
                if row is None:
                    continue
                rec["t"] = now_iso_ids
                rec["seen"] = now_iso_ids
                lead_status = (row.get("leadStatus") or "").strip()
                rec["ls"] = lead_status or None
                if rec.pop("gone", None):
                    rec.pop("gp", None)
                    rec.pop("g404", None)
                yield row

        @dlt.resource(
            name="opportunity_deletions",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunity_deletions_by_id():
            # Flushes markers queued in state. dlt interleaves resources, so a
            # 404 detected in this same run may not be visible yet - it is then
            # emitted by the next run (the webhook worker runs every 5 minutes).
            st = dlt.current.source_state()
            opps = _migrate_opp_state(st, now_iso_ids)
            for opp_id, rec in sorted(opps.items()):
                if rec.pop("gp", None):
                    src_label = "detail_404" if rec.get("g404") else "sweep_disappearance"
                    yield stamp({"id": opp_id, "_deleted_at": extracted_at, "_delete_source": src_label})

        yield opportunities_enriched_by_id
        yield opportunity_deletions_by_id

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
        # that changed, or went stale, get the expensive per-opp call. Watermark
        # lives in dlt source state (persisted in the destination, so it behaves
        # identically on duckdb and postgres). dlt extracts resources in yield
        # order, single-threaded, so the run-scoped sets below are fully populated
        # by the time the deletions resource runs (yielded last).
        #
        # THREE change detectors, because no single one is sufficient:
        #   1. sweep hash   - catches status / service date / job changes. Cheap
        #                     and immediate, but structurally blind to money and
        #                     leadStatus (see _opp_hash).
        #   2. staleness TTL - bounded blindness. Hot rows refresh daily, cold
        #                     rows fortnightly. A flat 24h TTL over the whole
        #                     window would cost ~42k calls/month on `local`.
        #   3. report queue  - marts.mart_enrichment_candidates, fed by the daily
        #                     zero-quota reports, targets exactly the opportunities
        #                     whose money or status the sweep cannot see.
        sweep_from = _ymd(today_local + timedelta(days=from_offset))
        sweep_to = _ymd(today_local + timedelta(days=to_offset))
        hot_from = _ymd(today_local - timedelta(days=3))
        hot_to = _ymd(today_local + timedelta(days=21))
        prune_before = _ymd(today_local - timedelta(days=120))
        now_dt = datetime.now(timezone.utc)
        # Microsecond precision on purpose: this timestamp orders runs against each
        # other for presence detection. At second resolution two runs in the same
        # second compare equal and a disappearance is silently missed.
        now_iso = now_dt.isoformat()

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
            # Only a sweep that paginated to completion proves absence. If the
            # budget trips or the API errors mid-walk this never runs, so the
            # deletion pass keeps using the previous complete sweep instead of
            # concluding that every unvisited opportunity vanished.
            dlt.current.source_state()["sweep"] = {
                "at": now_iso, "from": sweep_from, "to": sweep_to,
            }

        @dlt.transformer(
            data_from=enrich_sweep,
            name="opportunities_enriched",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunities_enriched(customer):
            st = dlt.current.source_state()
            opps = _migrate_opp_state(st, now_iso)
            for opp in customer.get("opportunities") or []:
                opp_id = opp.get("id")
                if not opp_id:
                    continue
                opp_id = str(opp_id)
                rec = opps.setdefault(opp_id, {})

                # Record presence facts on every sighting, enriched or not. `seen`
                # is what the deletion pass compares against; the service span is
                # what makes a later absence meaningful; and a reappearance clears
                # any prior soft-delete marker.
                rec["seen"] = now_iso
                sd_min, sd_max = _opp_service_span(opp)
                if sd_min is not None:
                    rec["sd"], rec["sdx"] = sd_min, sd_max

                # Reappearance after a soft delete. Force a fresh snapshot even if
                # the hash and TTL say otherwise: downstream decides "present
                # again" by comparing _sm_snapshot_at to _deleted_at, so clearing
                # the marker without re-enriching would leave the opportunity
                # looking deleted until its TTL happened to expire.
                resurrected = bool(rec.pop("gone", None))
                if resurrected:
                    rec.pop("gp", None)
                    rec.pop("g404", None)

                h = _opp_hash(opp)
                age_h = _hours_since(rec.get("t"), now_dt)
                sd_ref = rec.get("sd")
                ttl = cold_ttl_hours
                if sd_ref is not None and hot_from <= sd_ref <= hot_to:
                    ttl = hot_ttl_hours
                stale = age_h is None or age_h >= ttl
                forced = refresh_stale_hours is not None and (age_h is None or age_h >= refresh_stale_hours)

                if not (rec.get("h") != h or stale or forced or resurrected):
                    continue  # unchanged, fresh enough - no API call

                row, missing = enrich_one(opp_id)
                if missing:
                    # 404 = gone at source. Direct proof, independent of the sweep.
                    rec["gone"], rec["gp"], rec["g404"] = now_iso, True, True
                    continue
                if row is None:
                    continue  # transient empty body - leave the watermark alone so we retry
                # Only bank the watermark AFTER a successful call. Advancing it
                # first meant a failed detail call was never retried.
                rec["h"] = h
                rec["t"] = now_iso
                lead_status = (row.get("leadStatus") or "").strip()
                rec["ls"] = lead_status or None
                yield row

        @dlt.resource(
            name="opportunity_deletions",
            primary_key=("source_instance_id", "id"),
            write_disposition="merge",
        )
        def opportunity_deletions():
            # Opportunities a COMPLETED sweep should have seen but did not =
            # disappeared (cancelled/deleted at source). Raw never physically
            # deletes: we record a marker, and dbt treats a later enriched
            # snapshot as "present again".
            #
            # This is evaluated against the last sweep recorded as complete in
            # state, NOT against a within-run flag. dlt interleaves resources
            # round-robin, so this resource can run before the sweep it sits
            # next to has finished - any same-run presence diff is a coin flip.
            # Reading the last completed sweep is correct either way: if the
            # sweep already finished this run, detection is immediate; if not,
            # it lands on the next run. Deletion is a backstop anyway - the
            # `opportunity-deleted` webhook drives the 404 path immediately.
            st = dlt.current.source_state()
            opps = _migrate_opp_state(st, now_iso)

            sweep = st.get("sweep") or {}
            swept_at = _parse_iso(sweep.get("at"))
            if swept_at is not None:
                s_from, s_to = sweep.get("from"), sweep.get("to")
                for rec in opps.values():
                    if rec.get("gone"):
                        continue
                    seen_at = _parse_iso(rec.get("seen"))
                    if seen_at is None or seen_at >= swept_at:
                        continue  # never tracked, or present in that sweep
                    sd_min, sd_max = rec.get("sd"), rec.get("sdx")
                    if sd_min is None or sd_max is None:
                        continue  # no service date - absence proves nothing
                    if s_from is None or s_to is None or sd_max < s_from or sd_min > s_to:
                        continue  # outside that sweep's reach; the window slides
                    rec["gone"], rec["gp"] = now_iso, True

            for opp_id, rec in sorted(opps.items()):
                if rec.pop("gp", None):
                    src_label = "detail_404" if rec.get("g404") else "sweep_disappearance"
                    yield stamp({"id": opp_id, "_deleted_at": extracted_at, "_delete_source": src_label})

            # Bound the state blob: it is written to the destination on every run,
            # and previously grew without limit.
            for opp_id in [
                k for k, v in opps.items()
                if (v.get("sdx") is not None and v.get("sdx") < prune_before)
                or (v.get("sdx") is None and (_hours_since(v.get("t"), now_dt) or 0) > 120 * 24)
            ]:
                del opps[opp_id]

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
