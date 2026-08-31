#!/usr/bin/env python3
"""Deterministic synthetic support-ticket corpus generator (moss-quill)."""
import argparse, random

KW = {
    "billing": "invoice refund charge receipt proration credit card payment vat coupon overcharge autopay statement renewal price tier downgrade wire debit subtotal dispute reversal ledger invoice_id chargeback receipts billing due billed billed_id payout stripe tax remittance currency payout_id wallet".split(),
    "bug": "crash error stack freeze exception timeout leak regression failing deadlock corrupt glitch stuck panic traceback segfault hang spike outage rollback coredump overflow underflow race deadlock_id assert abort coredump_id bug broken fail crashloop watcher heap thrash jitter flake".split(),
    "howto": "export configure setup install license sync migrate webhook token permission sso quota howto enable disable integration key scope rotate provision import connect pair enroll delegate grant revoke mapping template wizard checklist walkthrough onboarding tutorial faq docs".split(),
}
IDIOM = {
    "billing": ["double charge", "credit card", "billing cycle", "refund policy",
                "price change", "payment failed", "annual plan", "tax invoice"],
    "bug": ["stack trace", "core dump", "null pointer", "error 500", "race condition",
            "memory leak", "crash loop", "failed request"],
    "howto": ["access token", "setup guide", "admin panel", "api key", "single sign",
              "role assignment", "data export", "step guide"],
}
SHARED = ["account", "server", "client", "version", "update", "dashboard", "app",
          "portal", "workspace", "profile", "plan", "email", "report", "log"]
FILLER = ["the", "a", "please", "help", "thanks", "issue", "when", "after", "since",
          "our", "team", "user", "still", "again", "seems", "tried", "every", "check",
          "also", "however", "maybe", "thing", "weird", "actually", "anyway"]

def make_row(rng):
    label = rng.choice(["billing", "bug", "howto"])
    parts = []
    if rng.random() < 0.5:
        parts.append(rng.choice(IDIOM[label]))
    parts += [rng.choice(KW[label]) for _ in range(rng.randint(1, 2))]
    parts += [rng.choice(KW[rng.choice(list(KW))]) for _ in range(rng.randint(0, 1))]
    parts += [rng.choice(SHARED) for _ in range(rng.randint(1, 3))]
    parts += [rng.choice(FILLER) for _ in range(rng.randint(2, 5))]
    rng.shuffle(parts)
    return label, " ".join(parts)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--count", type=int, default=2400)
    ap.add_argument("--edge", type=int, default=0)
    ap.add_argument("--flip", type=float, default=0.01)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    labels = ["billing", "bug", "howto"]
    rows = []
    for _ in range(a.count):
        lab, text = make_row(rng)
        if rng.random() < a.flip:
            lab = rng.choice(labels)
        rows.append((lab, text))
    lines = ["%s\t%s" % (l, t) for l, t in rows]
    if a.edge:
        extra = ["" for _ in range(a.edge // 4)]
        extra += [rng.choice(["no tab here", "onlytabs\t\t", "\t", "   "]) for _ in range(a.edge // 4)]
        extra += ["%s\t%s" % (rng.choice(labels), rng.choice(["!!!??? ...", "---", "???", "!!! ..."]))
                  for _ in range(a.edge - len(extra))]
        for e in extra:
            lines.insert(rng.randrange(len(lines) + 1), e)
        for _ in range(20):
            lines.append(rng.choice(lines))
        rng.shuffle(lines)
    with open(a.out, "w") as fh:
        fh.write("\n".join(lines) + "\n")

if __name__ == "__main__":
    main()
