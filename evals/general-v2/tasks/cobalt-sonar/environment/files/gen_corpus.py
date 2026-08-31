#!/usr/bin/env python3
"""Deterministic synthetic support-ticket corpus generator.

Usage: python3 gen_corpus.py --out OUT.tsv --seed SEED --count N --edge 0|1
Rows:  label<TAB>text  with labels billing / outage / feature.
Deterministic given (seed, count, edge).
"""
import argparse
import os
import random

BILLING = [
    "charged twice", "duplicate charge", "refund request", "invoice amount",
    "billing cycle", "payment failed", "card declined", "proration credit",
    "overcharged invoice", "receipt missing", "subscription price",
    "annual plan renewal", "coupon code", "tax charged", "wire transfer fee",
    "auto renew charge", "prorated refund", "statement balance", "vat number",
    "purchase order", "credit memo", "chargeback dispute", "billing address",
    "payment method expired", "double billed",
]
OUTAGE = [
    "service down", "api returning 500", "login outage", "latency spike",
    "packet loss", "region unreachable", "status page incident", "server crash",
    "connection timeout", "degraded performance", "downtime window",
    "error rate spike", "cluster failover", "node unhealthy", "queue backlog",
    "dropped requests", "service restoration", "incident postmortem",
    "datacenter outage", "cascading failure", "rolled back deploy",
    "memory leak crash", "504 gateway timeout", "health check failing",
    "load balancer flapping",
]
FEATURE = [
    "feature request", "dark mode support", "export to csv", "api webhook",
    "custom dashboard", "keyboard shortcuts", "integration with slack",
    "bulk import", "audit log", "role based access", "sso integration",
    "mobile app parity", "notification settings", "template gallery",
    "workflow automation", "custom fields", "calendar sync", "tag hierarchy",
    "saved filters", "offline mode", "column reordering", "shared inbox",
    "white label option", "sandbox environment", "usage analytics",
]
FILLER = [
    "the", "my", "our", "team", "account", "please", "when", "since", "after",
    "again", "still", "every", "month", "week", "today", "yesterday", "morning",
    "suddenly", "constantly", "recently", "about", "with", "for", "from", "into",
    "keeps", "shows", "gets", "seems", "looks", "need", "want", "trying", "using",
    "started", "stopped", "cannot", "unable", "would", "could", "should", "help",
    "check", "fix", "update", "change", "reset", "add", "remove", "open", "close",
    "workspace", "dashboard", "profile", "settings", "billing", "portal",
    "instance", "tenant", "user", "admin", "client", "server", "app", "page",
    "support", "ticket", "issue", "problem", "error", "value", "number", "list",
    "data", "report", "email", "notice", "alert", "log", "panel", "window",
    "version", "release", "plan", "order", "record", "entry", "detail", "field",
    "option", "section", "column", "table", "graph", "chart", "metric", "count", "total", "summary", "status", "state", "mode", "level",
    "type", "kind", "small", "large", "new", "old", "main", "extra", "single",
    "multiple", "daily", "weekly", "monthly", "early", "late", "high", "low",
    "full", "empty", "weird", "odd", "wrong", "right", "correct", "broken",
    "working", "fine", "bad", "good", "great", "poor", "fast", "slow", "quick",
    "sometimes", "always", "never", "often", "maybe", "perhaps", "again", "twice",
    "hour", "minute", "second", "day", "night", "quarter", "period", "cycle",
    "team", "manager", "review", "audit", "trial", "demo", "quote", "offer",
    "deal", "discount", "bundle", "package", "tier", "seat", "license", "key",
    "token", "code", "hash", "link", "url", "page", "view", "screen", "button",
    "menu", "bar", "icon", "label", "title", "name", "id", "ref", "case",
]

TEMPLATES = [
    "{a} {f1} {b} {f2} {c}",
    "{f1} {a} {f2} {b} {c} {f3}",
    "{a} {b} {c} {f1} {f2}",
    "{f1} {f2} {a} {c} {b}",
    "{a} {f1} {b} {c}",
    "{c} {b} {a} {f1}",
]

# cross-class contamination: sprinkle a couple of foreign-class phrases
ALL = {"billing": BILLING, "outage": OUTAGE, "feature": FEATURE}


def make_row(rng, label):
    own = ALL[label]
    others = [p for l in ALL if l != label for p in ALL[l]]
    a, b, c = rng.sample(own, 3)
    tmpl = rng.choice(TEMPLATES)
    fill = rng.sample(FILLER, 4)
    noise_pool = rng.random() < 0.55
    if noise_pool:
        # replace one own phrase with a foreign phrase (unigram ambiguity)
        idx = rng.randrange(3)
        foreign = rng.choice(others)
        a, b, c = (foreign, b, c) if idx == 0 else (a, foreign, c) if idx == 1 else (a, b, foreign)
    text = tmpl.format(a=a, b=b, c=c, f1=fill[0], f2=fill[1], f3=fill[2])
    extra = " ".join(rng.sample(FILLER, rng.randint(0, 3)))
    if extra:
        text = text + " " + extra
    return label, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--count", type=int, required=True)
    ap.add_argument("--edge", type=int, default=0)
    args = ap.parse_args()
    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(args.seed)
    rows = []
    for i in range(args.count):
        label = ["billing", "outage", "feature"][i % 3]
        rows.append(make_row(rng, label))
    rng.shuffle(rows)
    lines = ["%s\t%s" % (l, t) for l, t in rows]
    if args.edge:
        junk = [
            "", "   ", "no tab here at all", "billing",
            "unknown\trow with odd label", "\t", "billing\t   ",
            "billing\thelp me please with my invoice refund",
            "outage\tservice down again since yesterday",
            "feature\tadd bulk import to the dashboard please",
        ]
        lines = lines[: max(10, len(lines) - len(junk) + 2)] + junk
        rng.shuffle(lines)
    with open(args.out, "w") as f:
        for line in lines:
            f.write(line + "\n")


if __name__ == "__main__":
    main()
