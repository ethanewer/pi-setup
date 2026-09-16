#!/usr/bin/env python3
"""Deterministic generator for the gantry-budget workload.

A deployment is a directory containing:

  records.jsonl  -- one JSON object per line, a funding-request record
  config.json    -- deployment settings (token budget, quality floor)

Every record is generated from a fixed seed, so a given (out, count,
seed, ...) tuple is byte-reproducible. The narrative sections follow a
stable layout (REQUEST, FUNDING, JUSTIFICATION, POLICY, HISTORY,
BOILERPLATE); the facts that matter for summarisation live inside the
FUNDING and JUSTIFICATION prose, and nothing else in a record contains
an amount, an ISO date or an "Impact:" sentence.

Usage:
  python3 gen_records.py --out DIR --count N --seed S \
      [--budget TOKENS] [--floor RATIO] [--fluff SCALE]
      [--impact-min W] [--impact-max W]
"""
import argparse
import json
import os
import random

# Flavour sentences are deliberately free of digits, currency symbols,
# ISO dates and "Impact:" so extraction stays unambiguous.
FLAVOR = [
    "The operations group reviews the roster agreements",
    "No further submissions are applied within the current window",
    "The analysts keep a running journal of the assigned work",
    "Re-sequencing of the pipeline must first be approved by the desk",
    "The team maintains the quarterly log on the shared server",
    "Auditors sample the deliverables at the end of each period",
    "The measured drift stays inside the documented tolerance band",
    "The clerk routes the finished packets to the staging queue",
    "Schema revisions are recorded in the change ledger",
    "The equipment is re-calibrated before each auction attempt",
    "The task is deferred to the standing review board",
    "Counterexamples are added to the reproduction corpus",
    "Local mirrors refresh their aggregates on the nightly cycle",
    "The hand-off proceeds only after the counts reconcile",
    "The registry applies the new handler without touching the archive",
    "The diagnostic loop runs twice on the requested slot",
    "The report flags the entries that fall outside the band",
    "The preview build keeps the documented assumptions fixed",
    "The alarm is annotated with a purpose tag by the duty shift",
    "The formatter is idempotent across the fields under contract",
    "The distributor feeds the sanctioned examples to the consumers",
    "The caretaker rotates the cipher tables at the stated boundary",
    "No transition is recorded for the paused entry this turn",
    "The verifier compares the final two copies in read-only mode",
    "The custodian restores the snapshot from the secondary tier",
    "The latency probe runs at two minute cadence as specified",
    "The pointer is re-checked against the declared inventory",
    "The signing key is stored away from the documents it signs",
    "The reconcile step drops the stale tuples before committing",
    "The outlook page is rebuilt from the last good diff only",
    "The monitor polls the feed and retries the masked fetch",
    "The draft refresh is deferred until the load stabilises",
    "The trail is compacted once the mirror query crosses the threshold",
    "The board reviews the mapping at the next standing session",
    "The pool assigns the reserve slots only when the queue drains",
    "The blotter reflects the attempt entry by the duty officer",
    "The procedure forbids editing the transform after sign-off",
    "The cache retains the setting chosen by the lead engineer",
    "The operative notebook is re-run at the start of every review",
    "The trimmer drops the malformed case before the parser runs",
    "The ward keeps fifty cycles of history for the members",
    "The tie-breaker falls back to the original submitter",
    "The summary paragraph is frozen after the final edit",
    "The environment is redeployed only after the smoke checks",
    "The reconciliation note is attached to the release ticket",
    "The forecast is refreshed from the tier that the team pinned",
    "The backlog is trimmed to the items that the desk prioritised",
]

NOUNS = [
    "channel", "meridian", "cascade", "lantern", "raster", "gantry",
    "quash", "coupler", "vessel", "mantle", "corridor", "truss",
    "deck", "anchor", "relay", "buffer", "mosaic", "spiral", "wafer",
    "famish", "coronet", "valley", "furnace", "harbor", "lattice",
]

ADJECTIVES = [
    "annual", "tethered", "quiet", "radial", "salient", "bounded",
    "nominal", "focal", "oblique", "axial", "sparse", "velvety",
    "stacked", "glossy", "frosted", "nimble", "amber", "crisp",
]

VERBS = [
    "reconciles", "tracks", "fastens", "reviews", "scopes", "pipes",
    "caches", "samples", "forks", "blends", "reports", "quarantines",
    "strips", "flushes", "indexes", "merges", "lints", "drains",
]

IMPACT_LEAD = [
    "the revised ledger plan", "the rotated credential bundle",
    "the companion rangefinder pack", "the client dispatch token",
    "the mirrored audit canvas", "the primed checkpoint window",
    "the licensed radio scheduler", "the fold manifest digest",
    "the indexed annotation store", "the runbook mass refresh",
    "the cached draft policy", "the trimmed telemetry bucket",
    "the rendezvous slot calendar", "the quarantine buffer archive",
    "the onboarding trail", "the clamp recovery window",
]

IMPACT_VERB = [
    "keeps", "reserves", "restores", "reorders", "extends", "clamps",
    "streams", "diverts", "parallelises", "buffers", "elides", "forwards",
]

TAILS = ["procurement", "renewal", "audit", "refresh", "warrant",
         "retrofit", "sweep", "review", "rollout", "campaign"]


def para(rng, target_words):
    """Flavor paragraph of roughly target_words whitespace tokens."""
    words = 0
    out = []
    while words < target_words:
        sent = rng.choice(FLAVOR)
        out.append(sent + ".")
        words += len(sent.split())
    return " ".join(out)


def make_title(rng):
    return "%s %s %s" % (rng.choice(ADJECTIVES), rng.choice(NOUNS),
                         rng.choice(TAILS))


def make_impact(rng, min_words, max_words):
    """An 'Impact: ...' sentence with min_words..max_words tokens."""
    phrase = rng.choice(IMPACT_LEAD)
    used = len(phrase.split())
    extra = []
    while used < min_words:
        w = rng.choice(NOUNS)
        extra.append(w)
        used += 1
    max_extra = max_words - used
    more = max(0, min(6, max_extra))
    for _ in range(more):
        extra.append(rng.choice(NOUNS))
    body = phrase + ((" " + " ".join(extra)) if extra else "")
    return "Impact: %s %s the %s cadence." % (
        body, rng.choice(IMPACT_VERB), rng.choice(NOUNS))


def build_record(rng, idx, fluff_scale, impact_range):
    rid = "rec%05d" % idx
    title = make_title(rng)
    amount = "{:,.2f}".format(rng.uniform(800.0, 49000.0))
    due = "%04d-%02d-%02d" % (rng.randint(2024, 2030),
                              rng.randint(1, 12), rng.randint(1, 28))

    funding = (
        "The proposal requests a budget of %s dollars, committed for the "
        "work described in the request. The funds are due no later than "
        "%s and will not be re-sequenced." % (amount, due)
    )

    min_w, max_w = impact_range
    impact = make_impact(rng, min_w, max_w)

    re_text = "Proposal: %s. %s" % (title, para(rng, int(24 * fluff_scale) + 12))
    fund_text = funding + " " + para(rng, int(18 * fluff_scale) + 6)
    just_text = impact + " " + para(rng, int(30 * fluff_scale) + 24)
    policy_text = para(rng, int(120 * fluff_scale) + 40)
    hist_text = para(rng, int(80 * fluff_scale) + 30)
    bol_text = para(rng, int(300 * fluff_scale) + 120)

    return {
        "id": rid,
        "title": title,
        "sections": [
            {"head": "REQUEST", "text": re_text},
            {"head": "FUNDING", "text": fund_text},
            {"head": "JUSTIFICATION", "text": just_text},
            {"head": "POLICY", "text": policy_text},
            {"head": "HISTORY", "text": hist_text},
            {"head": "BOILERPLATE", "text": bol_text},
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--budget", type=int, default=700000)
    ap.add_argument("--floor", type=float, default=0.95)
    ap.add_argument("--fluff", type=float, default=1.0)
    ap.add_argument("--impact-min", type=int, default=16)
    ap.add_argument("--impact-max", type=int, default=30)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)
    rec_path = os.path.join(args.out, "records.jsonl")
    cfg_path = os.path.join(args.out, "config.json")
    with open(rec_path, "w") as fh:
        for i in range(args.count):
            rec = build_record(rng, i, args.fluff,
                               (args.impact_min, args.impact_max))
            fh.write(json.dumps(rec) + "\n")
    cfg = {
        "records_file": "records.jsonl",
        "budget_tokens": args.budget,
        "quality_floor": args.floor,
    }
    with open(cfg_path, "w") as fh:
        json.dump(cfg, fh, indent=2)
    print("wrote %d records to %s (budget %d, floor %.2f)" %
          (args.count, rec_path, args.budget, args.floor))


if __name__ == "__main__":
    main()