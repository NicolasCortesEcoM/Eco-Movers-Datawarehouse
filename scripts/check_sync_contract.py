#!/usr/bin/env python3
"""Fail if the repository has drifted from crm_sync_contract.md.

The contract is only worth having if something enforces it. Documentation that
nothing checks is documentation that quietly becomes fiction - which is exactly how
the same facts ended up written twelve ways in this repo.

Two classes of check:

  1. CODE MATCHES THE CONTRACT. The sweep window in the contract must equal the
     defaults in run.py and source.py. A doc that says [-180,+60] over code that
     does [-7,+30] is worse than no doc, because it is confidently wrong.

  2. FACTS ARE NOT DUPLICATED. Numbers that belong to the contract must not be
     restated anywhere else. This is the rule that stops the six contradictions
     from re-forming: correcting a duplicate is a temporary fix, deleting it is
     permanent.

Run: python scripts/check_sync_contract.py
Exit 0 = clean, 1 = drift found. Wire into CI or the daily build.
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = REPO / "crm_sync_contract.md"

# Files allowed to state these facts. Everything else must link to the contract.
#   - the contract itself is the authority
#   - smartmoving_api_findings.md is raw measurement and outranks the contract on
#     vendor behaviour, so its numbers are the source the contract cites
#   - this checker names the numbers in order to look for them
ALLOWED = {
    "crm_sync_contract.md",
    "smartmoving_api_findings.md",
    "scripts/check_sync_contract.py",
}

# Vendor artifacts and machine-generated files are never edited by us.
SKIP_DIRS = {"smartmoving_api_docs", ".git", "target", "logs", "dbt_packages",
             "__pycache__", "OLD_TABLES", "smartmoving_scheduble_reports"}

# Facts that must live in exactly one place. Pattern -> why it is dangerous.
SINGLE_SOURCE_FACTS = [
    (r"\[-7\s*,\s*\+?30\]",
     "the old sweep window; the contract says [-180,+60]"),
    (r"\[-7\s*,\s*\+?45\]",
     "the old reconciliation window that caused false deletions"),
    (r"~?\s*57,000",
     "a superseded quota estimate"),
    (r"~?\s*21,800",
     "a superseded quota estimate"),
    # 125,000 is a genuine vendor fact, so it is allowed to be *stated*. What is not
    # allowed is a second BUDGET built on it - that is the thing that went stale
    # twice. A heading or table caption is the tell.
    (r"#+\s*[^\n]*Quota Budget\s*\([^\n]*125,000",
     "a second quota budget; the contract holds the only one"),
    (r"42k\s+calls/month",
     "a superseded TTL cost estimate"),
    (r"4-5\s*(x|times)\s*(/|per\s+)day",
     "a superseded cadence; the contract defines the schedule"),
    # Freshness targets are a published obligation, so a stale copy is a promise
    # we are not keeping. serving_catalog.md carried "< 15 min" for jobs and leads
    # long after the contract had moved both to < 4 h - nobody noticed, because
    # nothing looked. Name the entity and link; never restate the number.
    (r"<\s*15\s*min",
     "a freshness target; section 8 of the contract holds the only copy"),
    (r"<\s*4\s*h\b",
     "a freshness target; section 8 of the contract holds the only copy"),
    (r"\*\*Freshness target\*\*",
     "a restated freshness target row; name the entity and link to the contract"),
]

# Claims that are simply false and must never reappear anywhere.
FALSEHOODS = [
    (r"Leads?\s*\|[^|\n]*Webhook",
     "there is NO lead-created webhook - leads are polling-only"),
    (r"[Nn]o per-second rate limit",
     "~120 calls/min is confirmed by measurement (429 observed)"),
]


def repo_markdown_and_code():
    for p in REPO.rglob("*"):
        if not p.is_file():
            continue
        if SKIP_DIRS & set(p.relative_to(REPO).parts):
            continue
        if p.suffix.lower() in {".md", ".py", ".sql", ".yml", ".yaml", ".json"}:
            yield p


def rel(p: pathlib.Path) -> str:
    return p.relative_to(REPO).as_posix()


def main() -> int:
    problems: list[str] = []

    if not CONTRACT.exists():
        print(f"FATAL: {rel(CONTRACT)} is missing - the contract IS the authority.")
        return 1

    contract_text = CONTRACT.read_text(encoding="utf-8")

    # --- Check 1: the contract's sweep window must match the code -------------
    #
    # Read the machine-readable marker, NOT the first [-N,+N] in the prose. The
    # contract legitimately mentions superseded windows while explaining why they
    # were replaced, and an earlier version of this check happily parsed one of
    # those and reported the code as broken.
    m = re.search(r"<!--\s*SWEEP_WINDOW:\s*(-?\d+)\s*,\s*\+?(-?\d+)\s*-->", contract_text)
    if not m:
        problems.append(
            "crm_sync_contract.md: missing the '<!-- SWEEP_WINDOW: -N,+N -->' marker"
        )
    else:
        want_from, want_to = int(m.group(1)), int(m.group(2))
        for path, pattern in [
            (REPO / "pipeline" / "run.py",
             r'"--from-offset".*?default=(-?\d+).*?\n.*?"--to-offset".*?default=(-?\d+)'),
            (REPO / "pipeline" / "sm_pipeline" / "source.py",
             r"from_offset:\s*int\s*=\s*(-?\d+),\s*\n\s*to_offset:\s*int\s*=\s*(-?\d+)"),
        ]:
            if not path.exists():
                continue
            got = re.search(pattern, path.read_text(encoding="utf-8"), re.S)
            if not got:
                problems.append(f"{rel(path)}: could not read the sweep defaults")
            elif (int(got.group(1)), int(got.group(2))) != (want_from, want_to):
                problems.append(
                    f"{rel(path)}: sweep default is "
                    f"[{got.group(1)},{got.group(2)}] but the contract says "
                    f"[{want_from},+{want_to}]"
                )

    # --- Check 2: single-source facts are not restated elsewhere --------------
    for path in repo_markdown_and_code():
        if rel(path) in ALLOWED:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for pattern, why in SINGLE_SOURCE_FACTS:
            for hit in re.finditer(pattern, text):
                line = text[: hit.start()].count("\n") + 1
                problems.append(
                    f"{rel(path)}:{line}: '{hit.group(0).strip()}' - {why}. "
                    f"Delete it and link to crm_sync_contract.md."
                )
        for pattern, why in FALSEHOODS:
            for hit in re.finditer(pattern, text):
                line = text[: hit.start()].count("\n") + 1
                problems.append(
                    f"{rel(path)}:{line}: FALSE CLAIM '{hit.group(0).strip()[:60]}' - {why}"
                )

    if problems:
        print(f"Sync-contract drift: {len(problems)} problem(s)\n")
        for p in problems:
            print("  " + p)
        print("\nThe contract is crm_sync_contract.md. Facts live there and nowhere else.")
        return 1

    print("Sync contract OK: code matches the contract, no duplicated facts found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
