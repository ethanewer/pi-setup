#!/usr/bin/env python3
"""Verifier for basalt-maze.

Starts fresh navd daemons (the depot default grid plus every hidden grid in
/tests/hidden), executes the deliverable /app/dispatch.py against each, and
independently validates the dispatch results:

  * the steps form a legal wall-avoiding walk from start to goal;
  * "final" equals the goal and "moves" == len(steps);
  * "token" matches the deterministic arrival-token formula recomputed here
    (never copied from the oracle);
  * the /app/route.json deliverable is a correct dispatch for the default grid;
  * on an unreachable-goal grid, dispatch.py exits non-zero within the time
    limit and creates no output file.

All parses are guarded; any failure -> reward 0.
"""
import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

APP = "/app"
DISPATCH = os.path.join(APP, "dispatch.py")
ROUTE = os.path.join(APP, "route.json")
NAVD = os.path.join(APP, "navd", "navd.py")
HIDDEN = "/tests/hidden"
DEFAULT_GRID = os.path.join(APP, "navd", "grid.json")

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def token_for(rows, cols, row, col, moves):
    s = "navd-v1|%dx%d|%d,%d|%d" % (rows, cols, row, col, moves)
    return hashlib.sha256(s.encode()).hexdigest()[:40]


class Navd:
    """A fresh navd daemon on an auto-picked loopback port."""

    def __init__(self, grid_path):
        self.proc = subprocess.Popen(
            [sys.executable, NAVD, grid_path, "0"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        line = self.proc.stdout.readline().decode().strip()
        if not line.startswith("LISTENING "):
            raise RuntimeError("navd did not announce: %r" % line)
        self.port = int(line.split()[1])

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def validate_dispatch(result_path, grid, ctx):
    """Validate a dispatch result JSON against its grid. Returns bool."""
    try:
        with open(result_path) as fh:
            got = json.load(fh)
    except Exception as exc:
        fail("%s: unreadable result JSON: %s" % (ctx, exc))
        return False
    try:
        assert isinstance(got, dict), "not a dict"
        assert set(got.keys()) == {"grid", "start", "goal", "steps",
                                   "final", "moves", "token"}, got.keys()
        rows, cols = grid["rows"], grid["cols"]
        assert got["grid"] == {"rows": rows, "cols": cols}, "grid mismatch"
        start = (grid["start"][0], grid["start"][1])
        goal = (grid["goal"][0], grid["goal"][1])
        assert (got["start"]["row"], got["start"]["col"]) == start, "start"
        assert (got["goal"]["row"], got["goal"]["col"]) == goal, "goal"
        walls = {(w[0], w[1]) for w in grid.get("walls", [])}
        steps = got["steps"]
        assert isinstance(steps, list), "steps not a list"
        assert all(s in ("N", "S", "E", "W") for s in steps), "bad step token"
        pos = start
        for i, s in enumerate(steps):
            dr, dc = {"N": (-1, 0), "S": (1, 0),
                      "E": (0, 1), "W": (0, -1)}[s]
            nxt = (pos[0] + dr, pos[1] + dc)
            assert 0 <= nxt[0] < rows and 0 <= nxt[1] < cols, \
                "step %d leaves grid" % i
            assert nxt not in walls, "step %d enters wall" % i
            pos = nxt
        assert (got["final"]["row"], got["final"]["col"]) == goal, \
            "final != goal"
        assert pos == goal, "steps do not end at goal"
        assert got["moves"] == len(steps), "moves != len(steps)"
        want = token_for(rows, cols, pos[0], pos[1], len(steps))
        assert got["token"] == want, \
            "token %r != recomputed %r" % (got["token"], want)
        return True
    except AssertionError as exc:
        fail("%s: %s" % (ctx, exc))
        return False
    except Exception as exc:
        fail("%s: unexpected validation error: %s" % (ctx, exc))
        return False


def run_dispatch(port, out_path, timeout=60):
    try:
        return subprocess.run(
            [sys.executable, DISPATCH, str(port), out_path],
            capture_output=True, text=True, timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        return None


def main():
    # The grader never hard-codes success: every expected value below is
    # recomputed from the grid files and the documented token formula.
    failures_present = False

    # --- visible deliverable: /app/route.json must dispatch the default grid
    try:
        with open(DEFAULT_GRID) as fh:
            default_grid = json.load(fh)
    except Exception as exc:
        print("FAIL: cannot read default grid: %s" % exc)
        return 1
    if not validate_dispatch(ROUTE, default_grid, "visible /app/route.json"):
        failures_present = True

    # --- deliverable program must exist and be runnable
    if not os.path.isfile(DISPATCH):
        fail("missing /app/dispatch.py")
        print("verify failures:", failures)
        return 1

    # --- hidden cases
    cases = sorted(os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
    if len(cases) < 2:
        fail("expected at least 2 hidden cases, found %r" % cases)
        failures_present = True
    free_port = 43990

    for case in cases:
        base = os.path.join(HIDDEN, case)
        grid_path = os.path.join(base, "grid.json")
        exp_path = os.path.join(base, "expected.json")
        if not (os.path.isfile(grid_path) and os.path.isfile(exp_path)):
            fail("hidden case %r malformed" % case)
            failures_present = True
            continue
        try:
            with open(grid_path) as fh:
                grid = json.load(fh)
            with open(exp_path) as fh:
                expected = json.load(fh)
        except Exception as exc:
            fail("hidden case %r fixtures unreadable: %s" % (case, exc))
            failures_present = True
            continue

        navd = None
        try:
            for _ in range(20):
                try:
                    sock = socket.socket()
                    sock.bind(("127.0.0.1", free_port))
                    sock.close()
                    break
                except OSError:
                    free_port += 1
            navd = Navd(grid_path)
        except Exception as exc:
            fail("hidden %r: navd failed to start: %s" % (case, exc))
            failures_present = True
            continue

        try:
            out = os.path.join(tempfile.gettempdir(),
                               "basalt_maze_%s.json" % case)
            if os.path.exists(out):
                os.remove(out)
            rc = run_dispatch(navd.port, out)
            reachable = bool(expected.get("reachable"))

            if not reachable:
                if rc is None:
                    fail("hidden %r: dispatch.py hung on unreachable goal"
                         % case)
                    failures_present = True
                elif rc == 0:
                    fail("hidden %r: dispatch.py exited 0 on unreachable goal"
                         % case)
                    failures_present = True
                elif os.path.exists(out):
                    fail("hidden %r: output file created for unreachable goal"
                         % case)
                    failures_present = True
                else:
                    print("hidden %r: unreachable handled (rc=%s)" % (case, rc))
            else:
                if rc is None:
                    fail("hidden %r: dispatch.py timed out" % case)
                    failures_present = True
                elif rc != 0:
                    fail("hidden %r: dispatch.py exited %s" % (case, rc))
                    failures_present = True
                elif not validate_dispatch(out, grid, "hidden %r" % case):
                    failures_present = True
                else:
                    print("hidden %r: ok" % case)
        finally:
            if navd is not None:
                navd.stop()

    print("verify failures:", failures)
    return 1 if failures_present else 0


if __name__ == "__main__":
    sys.exit(main())
