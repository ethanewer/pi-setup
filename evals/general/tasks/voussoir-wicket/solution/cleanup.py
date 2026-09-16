#!/usr/bin/env python3
"""meridian cleanup engine -- the "voussoir-wicket" real solver.

CLI:
    python3 cleanup.py <TREE_ROOT>

Prunes <TREE_ROOT> down to the size budget declared by the host's own
machine-readable cleanup policy (<TREE_ROOT>/policy.json), deleting only files
the policy classifies as junk, and never touching anything at or below the
paths listed in the host's retention manifest
(<TREE_ROOT>/<retention_manifest> from the policy).  Retained areas must be
preserved byte-for-byte: content, permissions, ownership and timestamps.

Deletion order is deterministic (oldest mtime first, then path) and the tool
stops as soon as the budget is met, so it never over-deletes.

Exit codes: 0 on success (budget met or fewer junk files than needed);
2 on any misuse or unreadable/missing policy or manifest.
"""
import json
import os
import stat
import sys

JUNK = None  # filled in main(); kept module-level for clarity


def fail(msg):
    sys.stderr.write("cleanup: %s\n" % msg)
    sys.exit(2)


def load_policy(root):
    p = os.path.join(root, "policy.json")
    try:
        with open(p, "r") as fh:
            pol = json.load(fh)
    except Exception as exc:
        fail("cannot read policy %s: %s" % (p, exc))
    if not isinstance(pol, dict):
        fail("policy is not a JSON object")
    budget = pol.get("budget_bytes")
    if not isinstance(budget, int) or budget < 0:
        fail("policy budget_bytes must be a non-negative integer")
    manifest = pol.get("retention_manifest")
    if not isinstance(manifest, str) or not manifest:
        fail("policy retention_manifest missing")
    junk = pol.get("junk")
    if not isinstance(junk, dict):
        fail("policy junk criteria missing")
    return pol, budget, manifest, junk


def load_manifest(root, name):
    p = os.path.join(root, name)
    roots = []
    try:
        with open(p, "r") as fh:
            for ln in fh:
                ln = ln.strip()
                if not ln or ln.startswith("#"):
                    continue
                roots.append(ln.rstrip("/"))
    except Exception as exc:
        fail("cannot read retention manifest %s: %s" % (p, exc))
    if not roots:
        fail("retention manifest %s lists no paths" % p)
    return roots


def in_retained(rel, roots):
    for r in roots:
        if rel == r or rel.startswith(r + "/"):
            return True
    return False


def is_junk(rel, size, junk):
    suffixes = junk.get("suffixes", [])
    prefixes = junk.get("prefixes", [])
    dir_names = junk.get("dir_names", [])
    min_size = junk.get("min_size_bytes", 0)
    if size < min_size:
        return False
    base = rel.rsplit("/", 1)[-1]
    if any(base.endswith(s) for s in suffixes):
        return True
    if any(base.startswith(p) for p in prefixes):
        return True
    parts = rel.split("/")
    if len(parts) > 1 and any(dn in parts[:-1] for dn in dir_names):
        return True
    return False


def tree_size(root):
    total = 0
    for _dp, _dns, fns in os.walk(root):
        for fn in fns:
            fp = os.path.join(_dp, fn)
            try:
                st = os.lstat(fp)
            except OSError:
                continue
            if stat.S_ISREG(st.st_mode):
                total += st.st_size
    return total


def main():
    if len(sys.argv) != 2:
        fail("usage: cleanup.py <TREE_ROOT>")
    root = sys.argv[1]
    if not os.path.isdir(root):
        fail("%s is not a directory" % root)

    pol, budget, manifest_name, junk = load_policy(root)
    roots = load_manifest(root, manifest_name)

    # --- collect junk candidates (never anything retained) ------------------
    candidates = []
    for dp, _dns, fns in os.walk(root):
        for fn in fns:
            fp = os.path.join(dp, fn)
            try:
                st = os.lstat(fp)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            rel = os.path.relpath(fp, root)
            if in_retained(rel, roots):
                continue
            if not is_junk(rel, st.st_size, junk):
                continue
            candidates.append((st.st_mtime_ns, rel, st.st_size, fp))

    total = tree_size(root)
    if total <= budget:
        print("cleanup: size %d already within budget %d; nothing to do"
              % (total, budget))
        return 0

    candidates.sort()  # oldest first; deterministic tie-break by path
    deleted = 0
    freed = 0
    for _mt, rel, size, fp in candidates:
        if total <= budget:
            break
        try:
            os.unlink(fp)
        except OSError as exc:
            sys.stderr.write("cleanup: cannot delete %s: %s\n" % (fp, exc))
            continue
        total -= size
        freed += size
        deleted += 1

    print("cleanup: deleted=%d freed=%d final=%d budget=%d"
          % (deleted, freed, total, budget))
    if total > budget:
        sys.stderr.write(
            "cleanup: warning: budget %d not met, final %d bytes; "
            "not enough deletable junk\n" % (budget, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())