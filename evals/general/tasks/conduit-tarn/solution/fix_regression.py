#!/usr/bin/env python3
"""conduit-tarn reference solver.

Performs the real work against /app/conduit:

  1. reproduce the TARN-4821 defect with the CLI on a basket feed,
  2. find the wrong grouping pass in conduit/aggregate.py and restore the
     documented semantics (every fill of a multi-row order survives, fills
     ordered by (timestamp, seq), orders in order of first appearance),
  3. add a regression test that fails on the shipped code and passes after,
  4. run the full suite and re-run the reproducer,
  5. commit the fix and the regression test without touching history.

The fix below is generated from the same contract the docs specify, not from
any hidden expectation.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = "/app/conduit"
AGGREGATE = os.path.join(REPO, "conduit", "aggregate.py")
TEST_FILE = os.path.join(REPO, "tests", "test_regression_basket_orders.py")

BASKET_FEED = (
    "order_id,side,instrument,quantity,price,timestamp\n"
    "BAS-1,BUY,TARNCORP,100,12.50,2025-03-01T09:00:01\n"
    "BAS-1,BUY,TARNCORP,150,12.40,2025-03-01T09:00:02\n"
    "BAS-2,SELL,ORNX,40,8.22,2025-03-01T09:01:00\n"
)

# Correct grouping: preserves pre-regression, documented behaviour.
FIXED_GROUP_ROWS = '''def group_rows(rows):
    """Group rows into orders, preserving the order of first appearance.

    A feed may carry several rows with the same order id: basket orders
    are split into one row per fill and every fill must survive into the
    order's fill list. Fills are ordered by timestamp, ties broken by
    feed position (seq).
    """
    groups = {}
    order_of = []
    for row in rows:
        if row.order_id not in groups:
            groups[row.order_id] = []
            order_of.append(row.order_id)
        groups[row.order_id].append(row)
    orders = []
    for oid in order_of:
        fills = sorted(groups[oid], key=lambda r: (r.timestamp, r.seq))
        orders.append((oid, fills))
    return orders
'''

REGRESSION_TEST = '''"""Regression test for TARN-4821: multi-leg basket orders.

Shipping version collapsed every order to a single representative fill, so a
basket order spanning several feed rows was reported with one fill and a
wrong gross. This suite must fail against the shipped code and pass once the
grouping pass keeps every fill.
"""
from datetime import datetime

from conduit.aggregate import group_rows, summarize
from conduit.orders import OrderRow


def _basket_rows():
    return [
        OrderRow("ORD-9001", "BUY", "TARNCORP", 100, 12.50,
                 datetime(2025, 1, 2, 9, 0, 1), 1),
        OrderRow("ORD-9001", "BUY", "TARNCORP", 150, 12.40,
                 datetime(2025, 1, 2, 9, 0, 2), 2),
    ]


def test_basket_order_keeps_every_fill():
    orders = group_rows(_basket_rows())
    assert len(orders) == 1
    order_id, fills = orders[0]
    assert order_id == "ORD-9001"
    assert len(fills) == 2


def test_basket_summary_uses_all_fills():
    orders = summarize(group_rows(_basket_rows()))
    order = orders[0]
    assert order["fill_count"] == 2
    assert order["gross"] == 3110.0
    assert order["sides"] == ["BUY"]
'''


def run(cmd, cwd=REPO, text=True, **kw):
    return subprocess.run(cmd, cwd=cwd, text=text, capture_output=True,
                          **kw)


def run_cli(feed_path, out_path):
    r = run([sys.executable, "-m", "conduit", feed_path, out_path])
    if r.returncode != 0:
        raise SystemExit("conduit CLI failed: %s" % r.stderr.strip())
    with open(out_path) as fh:
        return json.load(fh)


def fill_count(doc, order_id):
    for order in doc["orders"]:
        if order["order_id"] == order_id:
            return order["fill_count"]
    return None


def main():
    if not os.path.isdir(os.path.join(REPO, ".git")):
        raise SystemExit("no git repository at %s" % REPO)

    tmp = tempfile.mkdtemp(prefix="conduit-solve-")
    feed = os.path.join(tmp, "basket.csv")
    with open(feed, "w") as fh:
        fh.write(BASKET_FEED)
    out = os.path.join(tmp, "out.json")

    # 1) reproduce the defect at HEAD
    before = run_cli(feed, out)
    n_before = fill_count(before, "BAS-1")
    print("reproducer at HEAD: BAS-1 fill_count=%s (expected 1 while broken)"
          % n_before)

    # 2) restore the documented grouping pass
    src = open(AGGREGATE).read()
    if "collapsed" not in src:
        if n_before != 1:
            print("no collapse present and reproducer already correct; "
                  "nothing to fix")
        else:
            raise SystemExit("buggy collapse not found in aggregate.py")
    else:
        idx = src.index("def group_rows(")
        tail_marker = src.index("def summarize(")
        new_src = src[:idx] + FIXED_GROUP_ROWS + src[tail_marker:]
        with open(AGGREGATE, "w") as fh:
            fh.write(new_src)
        print("restored documented grouping in conduit/aggregate.py")

    # 3) the regression test
    with open(TEST_FILE, "w") as fh:
        fh.write(REGRESSION_TEST)
    print("wrote tests/test_regression_basket_orders.py")

    # 4) full suite must be green and the reproducer fixed
    pr = run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
              "tests/"])
    if pr.returncode != 0:
        raise SystemExit("suite not green after fix:\n%s" % pr.stdout[-2000:])
    after = run_cli(feed, out)
    n_after = fill_count(after, "BAS-1")
    if n_after != 2:
        raise SystemExit("reproducer still broken after fix: BAS-1 "
                         "fill_count=%s" % n_after)
    print("suite green; reproducer now reports BAS-1 fill_count=%s" % n_after)

    # 5) commit without rewriting history
    env = dict(os.environ)
    env["GIT_AUTHOR_NAME"] = "build"
    env["GIT_AUTHOR_EMAIL"] = "build@localhost"
    env["GIT_COMMITTER_NAME"] = "build"
    env["GIT_COMMITTER_EMAIL"] = "build@localhost"
    for args in (["add", AGGREGATE], ["add", TEST_FILE]):
        subprocess.run(["git", "-C", REPO] + args, check=True, env=env)
    staged = subprocess.run(
        ["git", "-C", REPO, "diff", "--cached", "--quiet"], env=env)
    if staged.returncode == 0:
        print("no changes staged; fix already committed")
    else:
        subprocess.run(
            ["git", "-C", REPO, "commit", "-q", "-m",
             "fix(aggregate): keep every fill of multi-leg basket orders"],
            check=True, env=env)
        head = subprocess.run(
            ["git", "-C", REPO, "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True)
        print("committed fix at %s" % head.stdout.strip())
    print("solver complete")


if __name__ == "__main__":
    main()