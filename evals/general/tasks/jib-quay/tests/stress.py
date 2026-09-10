#!/usr/bin/env python3
"""Verifier harness for jib-quay — the FX transfer-hub deadlock task.

Subcommands:

  case-run  CASE_DIR SERVICE_PATH LATENCY ITERS
        Runs ITERS concurrent iterations of the hidden mix against a fresh
        instance of SERVICE_PATH each time, plus a protocol probe run and
        SERIAL_RUNS serial timing runs.  Asserts, per iteration, that the run
        completes within a bounded deadline (no deadlock), that the journal
        is exactly the mix's transfer multiset with correct conversions, and
        that every account's reported balance matches a deterministic replay
        of the journal against the ledger.  Asserts the concurrency floor:
        the best concurrent iteration must finish in well under the best
        serial run (a single global lock or a single-threaded server keeps
        the ratio near 1.0 and fails).

  probe-pristine CASE_DIR SERVICE_PATH LATENCY
        Runs the hidden mix against the ORIGINAL shipped service (up to 3
        attempts) and requires at least one stalled run — the case must
        actually reproduce the seeded deadlock, or the fix could be vacuous.

  diagnosis  DIAG_PATH
        Loose content check of the agent's root-cause writeup.

  fixtures
        Hash-checks the pristine reference copies and the visible fixture
        copies, and requires the delivered /app/service.py to differ from the
        shipped original.

  imports  SERVICE_PATH
        Rejects third-party imports in the delivered service source.

Exit 0 only if the check passes; failures are printed to stdout.
"""
import ast
import hashlib
import json
import os
import socket
import subprocess
import sys
import threading
import time

STALL_GAP = 2.0            # no response this long with ops outstanding => stall
ITERATION_DEADLINE = 15.0  # whole-iteration bound (startup + mix + probes)
FLOOR_THRESHOLD = 0.85     # concurrent best must be < this * serial best
LATENCY_FRACTION = 0.8     # single transfer must take >= this * --latency
SERIAL_RUNS = 2
READY_TIMEOUT = 15.0

PRISTINE_FILES = [
    "/opt/pristine/service.py",
    "/opt/pristine/driver.py",
    "/opt/pristine/ledger.json",
    "/opt/pristine/mix_visible.json",
]
VISIBLE_PAIRS = [
    ("/app/driver.py", "/opt/pristine/driver.py"),
    ("/app/ledger.json", "/opt/pristine/ledger.json"),
    ("/app/mix_visible.json", "/opt/pristine/mix_visible.json"),
]
# sha256 of the ORIGINAL shipped files, frozen at author time.  A probe that
# reads a tampered pristine copy would prove nothing.
PRISTINE_SHA = {
    "/opt/pristine/service.py":
        "48ae4f97ff5e957eee8639e44e1fb49cab67bc7fea69ff0ddffcd9ba77bcc908",
    "/opt/pristine/driver.py":
        "16595a0e98496cd3d8fdf61adab20cae0ca22fbf2b5522e297a46ac504d0f99f",
    "/opt/pristine/ledger.json":
        "7085b964eff0e28f60b266326b2b34cb40792255376679138aba1c587fe3bf49",
    "/opt/pristine/mix_visible.json":
        "d8971b98b4262cdcee5f3ba18c677056e7eb02a5996e9c0dfd6c74dde0ef1dae",
}

_port_counter = [0]


def fresh_port():
    _port_counter[0] += 1
    return 21000 + (os.getpid() * 7 + _port_counter[0] * 13) % 20000


def sha256(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


class HarnessError(Exception):
    """A harness-level failure (service never became ready, crashed at start).
    These mean the verifier itself cannot measure, so they hard-fail."""


class ServiceProc:
    """Starts SERVICE --port P --ledger L --latency T and waits for READY."""

    def __init__(self, service, ledger, port, latency):
        self.port = port
        cmd = [sys.executable, service, "--port", str(port),
               "--ledger", ledger, "--latency", str(latency)]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True)
        ready = [False]
        err = []

        def wait_ready():
            try:
                line = self.proc.stdout.readline() if self.proc.stdout else ""
                ready[0] = line.startswith("READY")
                if not ready[0]:
                    err.append(line.strip())
            except Exception as exc:  # pragma: no cover
                err.append(repr(exc))

        th = threading.Thread(target=wait_ready, daemon=True)
        th.start()
        th.join(timeout=READY_TIMEOUT)
        if not ready[0]:
            self.close()
            raise HarnessError(
                "service %s did not print READY (stderr tail: %s)" %
                (service, (self.proc.stderr.read() or err)[-300:]))

    def close(self):
        try:
            self.proc.terminate()
        except ProcessLookupError:
            pass
        try:
            self.proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        try:
            self.proc.stderr.close()
        except OSError:
            pass


class WorkerClients:
    """Spawns `workers` client threads; each sends its op stream to the hub.
    Mirrors /app/driver.py so grading does not depend on any agent-editable
    file."""

    def __init__(self, port, streams, gap, deadline):
        self.port = port
        self.streams = streams
        self.gap = gap
        self.deadline = deadline
        self.results = []
        self.result_lock = threading.Lock()
        self.last_at = [0.0]
        self.stall = threading.Event()

    def _worker(self, widx, ops):
        try:
            sock = socket.create_connection(("127.0.0.1", self.port),
                                            timeout=self.deadline)
        except OSError:
            self.stall.set()
            return
        try:
            for op_index, op in enumerate(ops):
                line = "TRANSFER %s %s %d" % (op["src"], op["dst"], op["cents"])
                try:
                    sock.sendall(line.encode("ascii") + b"\n")
                except OSError:
                    self.stall.set()
                    return
                data = b""
                while not data.endswith(b"\n"):
                    try:
                        chunk = sock.recv(4096)
                    except socket.timeout:
                        self.stall.set()
                        return
                    if not chunk:
                        self.stall.set()
                        return
                    data += chunk
                resp = data.decode("ascii", "replace").strip()
                with self.result_lock:
                    self.results.append((widx, op_index, resp))
                    self.last_at[0] = time.monotonic()
        finally:
            try:
                sock.close()
            except OSError:
                pass

    def run(self, mix):
        """Returns (completed, elapsed)."""
        t0 = time.monotonic()
        threads = [threading.Thread(target=self._worker, args=(w, stream))
                   for w, stream in enumerate(self.streams)]
        for t in threads:
            t.start()
        deadline_at = t0 + self.deadline
        while not self.stall.is_set():
            now = time.monotonic()
            if now >= deadline_at:
                self.stall.set()
                break
            with self.result_lock:
                got = len(self.results)
                last = self.last_at[0] or t0
            if got >= len(mix["ops"]):
                break
            if (now - last) > self.gap:
                self.stall.set()
                break
            time.sleep(0.02)
        for t in threads:
            t.join(timeout=1.0)
        with self.result_lock:
            responses = sorted(self.results)
            elapsed = (self.last_at[0] - t0) if self.last_at[0] else 0.0
        completed = (not self.stall.is_set()) and len(responses) == len(mix["ops"])
        return completed, elapsed, responses


def fetch_control(port, accounts, recv_timeout=STALL_GAP):
    balances = {}
    journal = None
    stopped = False
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        sock.settimeout(recv_timeout)
    except OSError:
        return None, None, False

    def req(line):
        sock.sendall(line.encode("ascii") + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                raise EOFError
            data += chunk
        return data.decode("ascii", "replace").strip()

    try:
        for aid in accounts:
            r = req("BALANCE %s" % aid)
            balances[aid] = int(r[3:]) if r.startswith("OK ") else None
        rj = req("JOURNAL")
        if rj.startswith("OK "):
            try:
                journal = json.loads(rj[3:])
            except ValueError:
                journal = None
        r = req("STOP")
        stopped = (r == "BYE")
    except (OSError, EOFError):
        stopped = False
    finally:
        try:
            sock.close()
        except OSError:
            pass
    return balances, journal, stopped


def check_invariants(journal, balances, ops, ledger, failures, tag):
    """Deterministic ledger model: all transfers in `ops` succeed."""
    rates = {k: float(v) for k, v in ledger.get("rates", {}).items()}
    accounts = ledger["accounts"]
    curs = {a: spec["currency"] for a, spec in accounts.items()}

    def rate_for(sc, dc):
        return rates.get("%s-%s" % (sc, dc), 1.0)

    def converted_of(op):
        return int(round(op["cents"] * rate_for(curs[op["src"]], curs[op["dst"]])))

    expected_final = {a: int(spec["balance_cents"]) for a, spec in accounts.items()}
    mix_multiset = []
    for op in ops:
        mix_multiset.append((op["src"], op["dst"], op["cents"]))
        expected_final[op["src"]] -= op["cents"]
        expected_final[op["dst"]] += converted_of(op)

    if journal is None:
        failures.append("%s: no journal returned" % tag)
        return
    if len(journal) != len(ops):
        failures.append("%s: journal has %d entries, expected %d" %
                        (tag, len(journal), len(ops)))
        return
    got_multiset = []
    for entry in journal:
        try:
            tup = (entry["src"], entry["dst"], entry["cents"])
        except (KeyError, TypeError):
            failures.append("%s: malformed journal entry %r" % (tag, entry))
            return
        got_multiset.append(tup)
        want_conv = converted_of(entry)
        if entry.get("converted") != want_conv:
            failures.append("%s: entry %r converted=%r want %d" %
                            (tag, entry, entry.get("converted"), want_conv))
            return
    if sorted(got_multiset) != sorted(mix_multiset):
        failures.append("%s: journal transfer multiset does not match the "
                        "mix (missing/duplicated transfers)" % tag)
        return
    if balances is None:
        failures.append("%s: no balances returned" % tag)
        return
    for aid in accounts:
        want = expected_final[aid]
        got = balances.get(aid)
        if got is None or got != want:
            failures.append("%s: %s balance=%r want %d" % (tag, aid, got, want))
            return


def run_one_iteration(service, ledger_path, ledger, mix, workers, latency):
    """Runs the mix once.  Returns (completed, elapsed, responses, journal,
    balances).  Raises HarnessError on infrastructure failure (never READY,
    crash on startup).  A deadlocked service simply reports completed=False."""
    port = fresh_port()
    svc = ServiceProc(service, ledger_path, port, latency)
    try:
        streams = [[] for _ in range(workers)]
        for i, op in enumerate(mix["ops"]):
            streams[i % len(streams)].append(op)
        clients = WorkerClients(port, streams, STALL_GAP, ITERATION_DEADLINE)
        completed, elapsed, responses = clients.run(mix)
        balances = journal = None
        stopped = False
        if completed:
            balances, journal, stopped = fetch_control(port, list(ledger["accounts"]))
            completed = completed and stopped
        return completed, elapsed, responses, journal, balances
    finally:
        svc.close()


def run_protocol_probe(service, ledger_path, ledger, latency):
    """On a fresh service: latency step must take honest time, and the
    error paths (NOFUNDS / NOACCT / BAD / src==dst) plus BALANCE and JOURNAL
    must behave per contract.  Returns (ok, messages)."""
    port = fresh_port()
    svc = ServiceProc(service, ledger_path, port, latency)
    msgs = []
    try:
        accounts = list(ledger["accounts"].keys())
        first, second = accounts[0], accounts[1]
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        sock.settimeout(15)

        def req(line):
            sock.sendall(line.encode("ascii") + b"\n")
            data = b""
            while not data.endswith(b"\n"):
                chunk = sock.recv(65536)
                if not chunk:
                    raise EOFError
                data += chunk
            return data.decode("ascii", "replace").strip()

        t0 = time.monotonic()
        r = req("TRANSFER %s %s 100" % (first, second))
        dt = time.monotonic() - t0
        if not r.startswith("OK "):
            msgs.append("latency probe transfer returned %r" % r)
        elif dt < LATENCY_FRACTION * latency:
            msgs.append("latency probe too fast: %.3fs < %.3fs (latency step "
                        "not honored)" % (dt, LATENCY_FRACTION * latency))
        r = req("TRANSFER %s %s 50000000" % (first, second))
        if r != "NOFUNDS":
            msgs.append("expected NOFUNDS, got %r" % r)
        r = req("TRANSFER ghost %s 5" % first)
        if r != "NOACCT":
            msgs.append("expected NOACCT (bad src), got %r" % r)
        r = req("TRANSFER %s ghost 5" % first)
        if r != "NOACCT":
            msgs.append("expected NOACCT (bad dst), got %r" % r)
        r = req("BALANCE ghost")
        if r != "NOACCT":
            msgs.append("expected NOACCT (balance), got %r" % r)
        r = req("WIBBLE")
        if r != "BAD":
            msgs.append("expected BAD (unknown command), got %r" % r)
        r = req("TRANSFER %s %s nope" % (first, second))
        if r != "BAD":
            msgs.append("expected BAD (bad cents), got %r" % r)
        r = req("TRANSFER %s %s 0" % (first, second))
        if r != "BAD":
            msgs.append("expected BAD (zero cents), got %r" % r)
        r = req("TRANSFER %s %s 5" % (first, first))
        if r != "BAD":
            msgs.append("expected BAD (src==dst), got %r" % r)
        r = req("BALANCE %s" % first)
        if not r.startswith("OK "):
            msgs.append("expected OK balance, got %r" % r)
        r = req("JOURNAL")
        if not r.startswith("OK "):
            msgs.append("JOURNAL failed: %r" % r)
        else:
            try:
                j = json.loads(r[3:])
                if len(j) != 1 or j[0]["src"] != first or j[0]["cents"] != 100:
                    msgs.append("JOURNAL after probe malformed: %r" % r[:120])
            except ValueError:
                msgs.append("JOURNAL not JSON: %r" % r[:120])
        r = req("STOP")
        if r != "BYE":
            msgs.append("STOP replied %r" % r)
        sock.close()
        try:
            svc.proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            msgs.append("service did not exit after STOP")
    except (OSError, EOFError) as exc:
        msgs.append("protocol probe I/O error: %r" % exc)
    finally:
        svc.close()
    return (not msgs), msgs


def cmd_case_run(case_dir, service, latency, iters):
    failures = []
    ledger_path = os.path.join(case_dir, "ledger.json")
    mix_path = os.path.join(case_dir, "mix.json")
    with open(ledger_path, "r", encoding="utf-8") as fh:
        ledger = json.load(fh)
    with open(mix_path, "r", encoding="utf-8") as fh:
        mix = json.load(fh)
    workers = int(mix.get("workers", 1))
    ops = mix["ops"]
    tag = os.path.basename(case_dir.rstrip("/"))

    okp, msgp = run_protocol_probe(service, ledger_path, ledger, latency)
    if not okp:
        for m in msgp:
            failures.append("%s protocol: %s" % (tag, m))

    conc_elapsed = []
    for i in range(iters):
        try:
            completed, elapsed, _resps, journal, balances = run_one_iteration(
                service, ledger_path, ledger, mix, workers, latency)
        except HarnessError as exc:
            failures.append("%s: harness error on iteration %d: %s" % (tag, i, exc))
            break
        conc_elapsed.append(elapsed)
        if not completed:
            failures.append("%s: iteration %d did not complete within %.0fs "
                            "(deadlock/stall or incorrect serialization)" %
                            (tag, i, ITERATION_DEADLINE))
        else:
            check_invariants(journal, balances, ops, ledger, failures,
                             "%s iter%d" % (tag, i))

    serial_elapsed = []
    for i in range(SERIAL_RUNS):
        try:
            completed, elapsed, _resps, journal, balances = run_one_iteration(
                service, ledger_path, ledger, mix, 1, latency)
        except HarnessError as exc:
            failures.append("%s: harness error on serial run %d: %s" % (tag, i, exc))
            break
        serial_elapsed.append(elapsed)
        if not completed:
            failures.append("%s: serial run %d did not complete" % (tag, i))
        else:
            check_invariants(journal, balances, ops, ledger, failures,
                             "%s serial%d" % (tag, i))

    if conc_elapsed and serial_elapsed:
        best_c = min(conc_elapsed)
        best_s = min(serial_elapsed)
        ratio = best_c / best_s
        if ratio >= FLOOR_THRESHOLD:
            failures.append(
                "%s: concurrency floor not met: best concurrent %.3fs vs best "
                "serial %.3fs = %.2f (must be < %.2f; a global lock or a "
                "single-threaded server serializes everything)" %
                (tag, best_c, best_s, ratio, FLOOR_THRESHOLD))
        else:
            print("%s: floor ok ratio=%.2f (conc %.3fs / serial %.3fs)" %
                  (tag, ratio, best_c, best_s))

    if not failures:
        print("%s: PASS %d/%d concurrent iterations + %d serial runs" %
              (tag, iters - sum(1 for f in failures if "iteration" in f),
               iters, SERIAL_RUNS))
    return failures


def cmd_probe_pristine(case_dir, service, latency):
    ledger_path = os.path.join(case_dir, "ledger.json")
    with open(ledger_path, "r", encoding="utf-8") as fh:
        ledger = json.load(fh)
    with open(os.path.join(case_dir, "mix.json"), "r", encoding="utf-8") as fh:
        mix = json.load(fh)
    workers = int(mix.get("workers", 1))
    for attempt in range(3):
        try:
            completed, _elapsed, _r, _j, _b = run_one_iteration(
                service, ledger_path, ledger, mix, workers, latency)
        except HarnessError as exc:
            print("probe-pristine: harness error: %s" % exc)
            return False
        if not completed:
            print("probe-pristine: shipped service STALLED under the mix "
                  "(bug reproduces, attempt %d)" % (attempt + 1))
            return True
        print("probe-pristine: attempt %d completed (no stall)" % (attempt + 1))
    print("probe-pristine: shipped service completed the mix on all %d "
          "attempts; this case does not exercise the seeded deadlock" % 3)
    return False


def cmd_diagnosis(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        print("diagnosis: %s missing" % path)
        return False
    low = text.lower()
    ok = (len(text) >= 120 and
          "transfer" in low and
          "lock" in low and
          any(w in low for w in ("deadlock", "hang", "stall", "inversion",
                                 "cycle", "block")))
    if not ok:
        print("diagnosis: %s does not describe the deadlock (transfer + lock + "
              "stall word + length)" % path)
        return False
    print("diagnosis: content check passed")
    return True


def cmd_fixtures():
    problems = []
    for path in PRISTINE_FILES:
        h = sha256(path)
        want = PRISTINE_SHA[path]
        if h is None:
            problems.append("%s missing" % path)
        elif h != want:
            problems.append("%s has been modified (sha256 %s, want %s)" %
                            (path, h, want))
    for app_path, pristine_path in VISIBLE_PAIRS:
        if sha256(app_path) != sha256(pristine_path):
            problems.append("%s differs from its pristine reference" % app_path)
    deliv = sha256("/app/service.py")
    if deliv is None:
        problems.append("/app/service.py missing")
    elif deliv == sha256("/opt/pristine/service.py"):
        problems.append("/app/service.py is byte-identical to the shipped "
                        "original: nothing was repaired")
    if problems:
        for p in problems:
            print("fixtures: %s" % p)
        return False
    print("fixtures: pristine references intact, deliverable differs from "
          "the shipped original")
    return True


def cmd_imports(path):
    try:
        src = open(path, "r", encoding="utf-8").read()
    except OSError:
        print("imports: cannot read %s" % path)
        return False
    try:
        tree = ast.parse(src)
    except SyntaxError as exc:
        print("imports: %s is not valid python: %s" % (path, exc))
        return False
    bad = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                bad.add(a.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.module:
            bad.add(node.module.split(".")[0])
    allowed = set(sys.stdlib_module_names)
    stray = sorted(b for b in bad if b not in allowed)
    if stray:
        print("imports: non-stdlib imports in %s: %s" % (path, stray))
        return False
    print("imports: stdlib-only, parses clean")
    return True


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == "case-run":
        if len(argv) != 5:
            print("usage: case-run CASE_DIR SERVICE LATENCY ITERS")
            return 2
        case_dir, service, latency, iters = argv[1:]
        fails = cmd_case_run(case_dir, service, float(latency), int(iters))
        for f in fails:
            print("FAIL " + f)
        return 1 if fails else 0
    if cmd == "probe-pristine":
        if len(argv) != 4:
            print("usage: probe-pristine CASE_DIR SERVICE LATENCY")
            return 2
        ok = cmd_probe_pristine(argv[1], argv[2], float(argv[3]))
        return 0 if ok else 1
    if cmd == "diagnosis":
        return 0 if cmd_diagnosis(argv[1]) else 1
    if cmd == "fixtures":
        return 0 if cmd_fixtures() else 1
    if cmd == "imports":
        return 0 if cmd_imports(argv[1]) else 1
    print("unknown subcommand %r" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))