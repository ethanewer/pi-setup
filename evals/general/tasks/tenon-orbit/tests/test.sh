#!/bin/bash
# Verifier for tenon-orbit (executes-deliverable).
#
# The agent must deliver /app/quantum_dynamics.py: a Python program that
# evolves a two-level system with QuTiP (the real upstream package pinned and
# installed at build time) and reports the excited-state population P1(T) for
# the driven Hamiltonian H = -(delta/2) sigma_z + (omega/2) sigma_x.
#
# Layers of the check:
#   1. Static: the deliverable must reference QuTiP at all -- import, one of
#      its op/state constructors, and one of its solvers (sesolve/mesolve).
#   2. Numeric: on every hidden parameter set the printed P1(T) must match an
#      independently computed closed-form Rabi-flopping reference
#      |<1|exp(-iHT)|0>|^2 = (omega^2/W^2) sin^2(W T/2), W = sqrt(delta^2+omega^2),
#      within 2e-4.
#   3. Trust-of-origin (anti-spoof): the printed number must actually flow out
#      of the QuTiP solver. A fresh numpy script that hand-writes the closed
#      formula and decorates itself with a dead sesolve() call satisfies (1)
#      and (2) but not (3), so every case is re-run with qutip.sesolve and
#      qutip.mesolve replaced (via a sitecustomize stub) by an exact solver
#      whose result carries a known +0.1 upward shift. If the deliverable prints
#      a value that still equals the unshifted reference -- or crashes/prints
#      nothing -- its answer is demonstrably independent of QuTiP's solver and
#      the case fails.
#
# Reward is binary and written on every exit path.
set -u
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
mkdir -p /logs/verifier

DELIVERABLE="/app/quantum_dynamics.py"

if [ ! -f "$DELIVERABLE" ]; then
  echo "missing deliverable $DELIVERABLE" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# Ground the perturbed-solver stub in stdin; it is written to a temp dir that
# runs under $PYTHONPATH for the second (perturbed) run of each case.
python3 - "$DELIVERABLE" <<'PY'
import json
import math
import os
import subprocess
import sys
import tempfile
import textwrap

path = sys.argv[1]
failures = []


def fail(m):
    failures.append(m)


# ---- 1) The deliverable must genuinely reference QuTiP ----
try:
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
except Exception as e:  # noqa: BLE001
    fail("could not read deliverable: %r" % e)
    src = ""

has_import = ("import qutip" in src) or ("from qutip" in src)
# Uses a QuTiP solver and at least one QuTiP operator/state constructor.
# Names, not aliases, so "import qutip as q" is accepted.
has_solver = ("sesolve" in src) or ("mesolve" in src)
has_op = any(op in src for op in (
    "sigmax", "sigmaz", "sigmay", "sigmap", "sigmam",
    "Qobj", "ket", "bra", "basis", "identity",
    "destroy", "create", "project", "tensor", "fock"))
if not has_import:
    fail("deliverable does not import QuTiP (no 'import qutip' / 'from qutip')")
if not has_solver:
    fail("deliverable does not use a QuTiP solver (no sesolve/mesolve)")
if not has_op:
    fail("deliverable does not construct QuTiP operators/states (no sigmax/..., Qobj, ket, ...)")
if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# ---- independent closed-form reference for the Rabi model ----
def reference(delta, omega, T):
    W = math.sqrt(delta * delta + omega * omega)
    return (omega * omega / (W * W)) * math.sin(W * T / 2.0) ** 2

# ---- perturbed-solver stub (sitecustomize) ----
# Replaces qutip.sesolve / qutip.mesolve with an exact solver whose result
# carries a known +0.1 shift. Any honest program reads its printed value out
# of the solver result, so under the stub it prints reference+0.1. A program
# that printed a closed-form it computed itself prints the unshifted value.
PERTURB = 0.1

SITE = textwrap.dedent("""
    import math
    import numpy as np
    import scipy.linalg as sla
    import qutip as _q

    _PERTURB = 0.1

    class _FakeResult:
        def __init__(self, H, psi0, T):
            Hm = H.full() if hasattr(H, "full") else np.asarray(H, dtype=complex)
            psi0v = np.asarray(psi0.full(), dtype=complex).reshape(-1) if hasattr(psi0, "full") else np.asarray(psi0, dtype=complex).reshape(-1)
            U = sla.expm(-1j * Hm * T)
            v = U @ psi0v
            p0, p1 = abs(v[0]) ** 2, abs(v[1]) ** 2
            n = p0 + p1
            phase0 = (v[0] / abs(v[0])) if p0 > 0 else 1.0
            phase1 = (v[1] / abs(v[1])) if p1 > 0 else 1.0
            shifted = min(p1 / n + _PERTURB, 1.0)
            b1 = math.sqrt(shifted)
            b0 = math.sqrt(1.0 - shifted)
            w = np.array([phase0 * b0, phase1 * b1])
            self.expect = [[p1 / n + _PERTURB]]
            self.states = [_q.Qobj(w)]
            self.final_state = _q.Qobj(w)
            self.times = [float(T)]

    def _stub(*args, **kwargs):
        # signatures: sesolve(H, psi0, times, e_ops=[...], ...) or
        #             mesolve(H, psi0, times, c_ops, e_ops=[...], ...)
        H = args[0]
        psi0 = args[1]
        if len(args) > 2 and hasattr(args[2], "__len__"):
            tlist = args[2]
        else:
            tlist = kwargs.get("tlist") or kwargs.get("times") or [0.0]
        T = float(tlist[-1])
        return _FakeResult(H, psi0, T)

    _q.sesolve = _stub
    _q.mesolve = _stub
""")

stub_dir = tempfile.mkdtemp(prefix="qutip-stub-")
with open(os.path.join(stub_dir, "sitecustomize.py"), "w") as fh:
    fh.write(SITE)

# ---- 3) Hidden generalization cases ----
hidden = "/tests/hidden"
cases = sorted(n for n in os.listdir(hidden)
               if os.path.isdir(os.path.join(hidden, n)))
if len(cases) < 2:
    fail("expected >=2 hidden cases, found %d" % len(cases))

tolerance = 2e-4


def run_case(delta, omega, T, perturbed):
    env = dict(os.environ)
    if perturbed:
        base = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = stub_dir + (os.pathsep + base if base else "")
    r = subprocess.run(
        [sys.executable, path, str(delta), str(omega), str(T)],
        capture_output=True, text=True, env=env, cwd="/app")
    if r.returncode != 0:
        return None, "runtime error: " + r.stderr.strip()[:300]
    try:
        val = float(r.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        return None, "stdout not a float: %r" % r.stdout[:200]
    return val, None


bad = False
for case in cases:
    pj = os.path.join(hidden, case, "params.json")
    if not os.path.exists(pj):
        fail("%s: missing params.json" % case)
        continue
    with open(pj) as fh:
        p = json.load(fh)
    delta, omega, T = float(p["delta"]), float(p["omega"]), float(p["T"])
    val, err = run_case(delta, omega, T, perturbed=False)
    if err is not None:
        fail("%s: %s" % (case, err))
        continue
    want = reference(delta, omega, T)
    if abs(val - want) > tolerance:
        fail("%s: P1=%.10f want %.10f (diff %.2e > %.1e)"
             % (case, val, want, abs(val - want), tolerance))
        continue
    # Perturbed-solver run: the printed value must move with the solver.
    val2, err2 = run_case(delta, omega, T, perturbed=True)
    if err2 is not None:
        fail("%s: answer independent of QuTiP solver? perturbed run failed: %s"
             % (case, err2))
        continue
    if abs(val2 - (want + PERTURB)) > tolerance:
        fail("%s: printed value %.10f does not follow the QuTiP solver result "
             "(perturbed run gave %.10f, expected %.10f) -- the answer does "
             "not flow through qutip's sesolve/mesolve" % (case, val, val2, want + PERTURB))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS: QuTiP-based deliverable matched closed-form reference on %d hidden case(s) "
      "and the printed value tracks the QuTiP solver" % len(cases))
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY