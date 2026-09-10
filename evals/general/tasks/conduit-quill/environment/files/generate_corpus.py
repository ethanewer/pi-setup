#!/usr/bin/env python3
"""Deterministic generator for the conduit-quill RAG corpus and query sets.

Builds a fictional engineering knowledge base ("Orion Systems") of 400
documents across 100 themes, 4 documents per theme. It also emits query sets
with document-level relevance judgements: a visible dev set (written into
out_dir/dev/queries.json) and, on request, hidden query sets.

Structure (all deterministic from a fixed master seed):

  Each theme has:
    - a unique keyword (a distinctive technical term)
    - a unique synonym  (a different term for the same concept)
    - a pool of concept tokens (theme-specific vocabulary)

  4 documents per theme:
    doc[0] : contains BOTH the keyword and the synonym (this is what lets a
             corpus-derived co-occurrence embedding learn keyword ~ synonym)
    doc[1] : contains the keyword (lexical)
    doc[2] : contains the synonym only, NEVER the keyword  (the "hard" doc —
             a purely lexical retriever keyed on the query keyword misses it)
    doc[3] : contains the keyword (lexical)

Query relevance: a query for theme t is written using t's keyword, and its
relevant documents are exactly the 4 documents of theme t. Because doc[2]
never contains the query's only theme token, a retriever that relies on exact
token overlap (plain BM25) stays below the quality gate, while a retriever
that also uses a locally computed distributional (co-occurrence) embedding
reaches perfect recall.

Each query set also marks, per query, the ``narrow_doc``: the relevant
document written with different terminology, i.e. the one whose wording
shares no vocabulary with the query (doc[2] of the theme). This is the
cross-wording document the retrieval-quality gate requires a retriever to
still find.

Document ids are permuted AFTER generation so that the four documents of one
theme are never adjacent ids. The corpus file itself carries no theme label:
relevance can only be recovered from document CONTENT, which is the point of
the task. Titles are generic and carry no keyword.

Usage:
  python3 generate_corpus.py <out_dir>
      build corpus.json + dev/queries.json under <out_dir>
  python3 generate_corpus.py <out_dir> --hidden-set <setname> <seed> <theme_idx,...>
      additionally emit tests/hidden/<setname> query files for given themes

Run with a fixed corpus root so corpus.json and every query set reference the
same document ids.
"""
import json
import os
import random
import sys

MASTER_SEED = 20260411
SHUFFLE_SEED = 20260713
N_THEMES = 100
N_DOCS_PER_THEME = 4

# Technical-looking morphemes used to build unique tokens.
MORPHS = [
    "micro", "nano", "hyper", "quasi", "ultra", "meta", "iso", "acro",
    "para", "tele", "poly", "cryo", "helio", "meso", "ortho", "xeno",
    "ferro", "gyro", "kaldo", "neuo", "plaso", "reido", "sunno", "tarvo",
]
STEMS = [
    "quantile", "flux", "beam", "strand", "matrix", "shard", "mantle",
    "kernel", "facet", "solenoid", "gyre", "caliber", "telemetry", "gauge",
    "spindle", "resonator", "coupler", "absorber", "actuator", "scanner",
    "diffuser", "lathe", "retent", "buffer", "vane", "plenum", "stator",
    "camber", "spool", "manifold",
]

# Engineering-sounding sentence templates, {t} substituted with a token.
TEMPLATES = [
    "The {t} assembly is calibrated against the reference bench before each run.",
    "During commissioning we set the {t} tolerance band to two standard units.",
    "The {t} reading is cross-checked twice and then written to the shop ledger.",
    "Operators log the {t} offset whenever the line exceeds its nominal cadence.",
    "A failed {t} check triggers an immediate halt and a full re-inspection.",
    "We record the {t} drift alongside the ambient temperature in the daily log.",
    "The {t} fixture is re-torqued at the start of every shift batch.",
    "Maintenance queues the {t} overhaul once the vibration index crosses 0.4.",
    "Each {t} part is serialized and traced back to its casting lot code.",
    "The audit compares the {t} count against the rolling inventory snapshot.",
    "A second shift re-runs the {t} measurement to confirm the first reading.",
    "The station pulls the {t} sample and stores it in the climate cabinet.",
    "Shifts reconcile the {t} register against the supervisor sign-off sheet.",
    "Integration tests exercise the {t} path before the unit is released.",
    "We flagged the {t} anomaly and opened a corrective action ticket.",
    "The {t} calibration is due again and the badge reader logs the visit.",
    "Baseline the {t} value before the line-up and archive it afterwards.",
    "The {t} gauges are cross-referenced against the master reference set.",
    "Engineers review the {t} trend each week and note any step change.",
    "The revised {t} procedure supersedes the previous version in the manual.",
]

# Generic connective sentences to vary wording / lengthen documents.
# Every word used here is deliberately absent from the query lead-in/tail
# phrases (and vice versa), so the only query vocabulary that ever appears in
# a document is the theme keyword itself. That keeps "shares no query
# vocabulary" an exact and unique property of doc[2], the synonym-only
# document.
GENERIC = [
    "The line has run eleven thousand cycles since the last tear-down.",
    "We keep the raw records for seven years before they are archived.",
    "All changes are reviewed in the weekly stand-up.",
    "The supervisor signs the log at the end of every shift.",
    "Note that figures here are representative and are updated monthly.",
    "The plant operates on a two-shift pattern during the peak season.",
    "Every item carries a machine-readable tag for the warehouse scan.",
    "Thresholds were agreed with quality control in the spring review.",
    "Reports are generated automatically when the batch closes.",
    "The team meets on Thursday to close open corrective actions.",
]

# Generic, keyword-free titles (drawn deterministically per document).
TITLES = [
    "Orion Systems - calibration record",
    "Orion Systems - operations log",
    "Orion Systems - build journal",
    "Orion Systems - maintenance card",
    "Orion Systems - inspection sheet",
    "Orion Systems - field report",
]

LEADINS = [
    "Summarize how",
    "What does the documentation say about",
    "Explain the handling of",
    "Describe the current status of",
    "Detail the application of",
]
# Note: chosen so that NO word of any tail phrase is a corpus token (the
# corpus was generated with that constraint). That keeps the query's only
# theme signal the keyword itself.
TAIL = [
    "in the Orion production environment",
    "across the recent release window",
    "as recorded in the engineering handbook",
    "for the current build year",
    "per the ops handbook",
]


def token(a, b):
    return a + b


def build_themes(rng):
    """Return list of theme dicts with globally unique tokens."""
    # Build a large pool of unique tokens (both a+b and b+a combos), so the
    # pool comfortably exceeds the 100 themes x 12 tokens we need.
    pool = []
    seen = set()
    for a in MORPHS:
        for b in STEMS:
            for t in (a + b, b + a):
                if t not in seen:
                    seen.add(t)
                    pool.append(t)
    rng.shuffle(pool)
    themes = []
    pi = 0
    for i in range(N_THEMES):
        keyword = pool[pi]; pi += 1
        synonym = pool[pi]; pi += 1
        concept = [pool[pi + k] for k in range(10)]; pi += 10
        rng.shuffle(concept)
        themes.append({
            "id": "theme_%03d" % i,
            "keyword": keyword,
            "synonym": synonym,
            "concept": concept,
            "context": rng.choice(LEADINS),
        })
    return themes


def make_sentence(rng, token_choice, extra_head=None):
    """One sentence using a token from the theme; optionally prepend a phrase."""
    tpl = rng.choice(TEMPLATES)
    if extra_head:
        return extra_head + " " + tpl.format(t=token_choice)
    return tpl.format(t=token_choice)


def build_doc_text(rng, theme, which):
    """Compose a full document body for one of the 4 theme documents.

    Documents are kept long enough (~240 tokens) that a real chunker splits
    them; each chunk still maps back to its parent document."""
    kw, sy = theme["keyword"], theme["synonym"]
    conc = list(theme["concept"])
    rng.shuffle(conc)
    lines = []

    def add_n(token_choices):
        # 18 template sentences spread across the theme's concept tokens
        for c in range(18):
            lines.append(make_sentence(
                rng, token_choices[c % len(token_choices)]))

    # Every keyword document pairs kw with sy in the SAME sentence, repeatedly
    # across the theme, so kw and sy co-occur strongly in the corpus. The hard
    # doc (which==2) contains the synonym only, never the keyword.
    if which in (0, 1, 3):
        lines.append("The %s workflow is also referred to as %s in the "
                     "current documentation." % (kw, sy))
        lines.append(make_sentence(rng, sy))
        lines.append(make_sentence(rng, kw))
        rng.shuffle(GENERIC)
        lines.extend(GENERIC[:2])
        add_n(conc)
    # doc[2]: synonym only (HARD - keyword never appears)
    elif which == 2:
        lines.append(make_sentence(rng, sy))
        rng.shuffle(GENERIC)
        lines.extend(GENERIC[:2])
        add_n(conc)
    return " ".join(lines)


def build_corpus(out_dir):
    rng = random.Random(MASTER_SEED)
    themes = build_themes(rng)
    docs = []  # (theme_id, which, doc dict), doc ids consecutive by theme yet
    for t in themes:
        for w in range(N_DOCS_PER_THEME):
            did = "doc_%05d" % len(docs)
            rng = random.Random(MASTER_SEED + len(docs))
            title = rng.choice(TITLES)
            body = build_doc_text(rng, t, w)
            docs.append((t["id"], w, {
                "doc_id": did,
                "title": title,
                "body": body,
            }))
    # Deterministic id permutation: decouple id adjacency from theme
    # membership so relevance is not readable off id locality.
    perm = list(range(len(docs)))
    random.Random(SHUFFLE_SEED).shuffle(perm)
    docs = [docs[i] for i in perm]
    for n, (th, w, d) in enumerate(docs):
        d["doc_id"] = "doc_%05d" % n
    docs_out = [d for (_, _, d) in docs]

    theme_docs = {}
    narrow_map = {}
    for th, w, d in docs:
        theme_docs.setdefault(th, []).append(d["doc_id"])
        if w == 2:
            narrow_map[th] = d["doc_id"]

    with open(os.path.join(out_dir, "corpus.json"), "w") as fh:
        json.dump(docs_out, fh, indent=1)
    return docs_out, themes, theme_docs, narrow_map


def query_text_for(rng, theme):
    lead = rng.choice(LEADINS)
    tail = rng.choice(TAIL)
    return "%s %s %s." % (lead, theme["keyword"], tail)


def emit_query_set(themes, theme_docs, narrow_map, theme_indices, rng_seed,
                   path):
    """Write a queries.json with relevance judgements for given theme indices.

    Query entries carry the query text, the relevance judgement, and the
    ``narrow_doc`` marker naming the relevant document written with different
    wording (no shared query vocabulary). There is no topic label linking a
    query to its relevant documents, so relevance can only be recovered from
    document content."""
    rng = random.Random(rng_seed)
    queries = []
    for idx in theme_indices:
        t = themes[idx]
        relevant = sorted(theme_docs[t["id"]])
        qid = "q_%03d" % len(queries)
        queries.append({
            "query_id": qid,
            "query": query_text_for(rng, t),
            "relevant_doc_ids": relevant,
            "narrow_doc": narrow_map[t["id"]],
        })
    with open(path, "w") as fh:
        json.dump(queries, fh, indent=1)
    return queries


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    docs, themes, theme_docs, narrow_map = build_corpus(out_dir)

    # Visible dev query set: themes 0..17 (18 queries).
    dev_dir = os.path.join(out_dir, "dev")
    os.makedirs(dev_dir, exist_ok=True)
    dev_indices = list(range(0, 18))
    emit_query_set(themes, theme_docs, narrow_map, dev_indices, 91234,
                   os.path.join(dev_dir, "queries.json"))

    if "--hidden-set" in sys.argv:
        i = sys.argv.index("--hidden-set")
        setname = sys.argv[i + 1]
        seed = int(sys.argv[i + 2])
        indices = [int(x) for x in sys.argv[i + 3].split(",")]
        hdir = os.path.join(out_dir, "tests", "hidden", setname)
        os.makedirs(hdir, exist_ok=True)
        emit_query_set(themes, theme_docs, narrow_map, indices, seed,
                       os.path.join(hdir, "queries.json"))
        print("wrote hidden set", setname, indices)

    print("corpus docs:", len(docs))
    print("dev queries:", len(dev_indices))


if __name__ == "__main__":
    main()