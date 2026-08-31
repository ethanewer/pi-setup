#!/bin/bash
# Verifier for kestrel-marsh (executes-deliverable).
#
# Executes the deliverable /app/setup_r_env.sh, enforces the no-modify rule on
# the supplied /app/analysis inputs, validates the executed-notebook deliverable
# /app/analysis/causal_probe.executed.ipynb, and re-executes the visible probe
# plus every hidden R probe notebook through the registered causalr kernel.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible inputs (the instruction forbids
# modifying them; tampering would defeat the visible-case execution check).
PRISTINE_NB_SHA="fd83b6e193478102d736709725590141f1f031b8f85e2584d92668ba96eb4943"
PRISTINE_DAG_SHA="2e200acb6164188fd5143e2bd1013458ccd185f5b7334dc94aec47340e1f4d3b"

no_modify_broken=0
for pair in "/app/analysis/causal_probe.ipynb:$PRISTINE_NB_SHA" "/app/analysis/dag.json:$PRISTINE_DAG_SHA"; do
    path="${pair%%:*}"; want="${pair##*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        [ "$actual" = "$want" ] || { echo "no-modify: $path modified" >&2; no_modify_broken=1; }
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, re, subprocess, sys

SETUP = "/app/setup_r_env.sh"
EXECUTED_NB = "/app/analysis/causal_probe.executed.ipynb"
VISIBLE_NB = "/app/analysis/causal_probe.ipynb"
VISIBLE_MARKERS = ["CAUSAL_PROBE_V1", "DAG nodes=4 edges=4 sources=2", "SQSUM=385"]
no_modify_broken = int(sys.argv[1])
probs = []


def check(name, cond, detail=""):
    if not cond:
        probs.append("%s  <%s>" % (name, detail))


def cell_text(nb):
    """Collect every piece of textual output from an executed notebook."""
    chunks = []
    for cell in nb.get("cells", []):
        for out in cell.get("outputs", []):
            if out.get("output_type") == "stream":
                chunks.append("".join(out.get("text", [])))
            elif out.get("output_type") in ("execute_result", "display_data"):
                data = out.get("data", {})
                if "text/plain" in data:
                    chunks.append("".join(data["text/plain"]))
    return "\n".join(chunks)


def exec_markers(path, timeout=120):
    """Execute a notebook with the causalr kernel; return (ok, text)."""
    out = "/tmp/kestrel_marsh_exec_%d.ipynb" % os.getpid()
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        ["jupyter", "nbconvert", "--to", "notebook", "--execute",
         "--ExecutePreprocessor.kernel_name=causalr",
         "--ExecutePreprocessor.timeout=120",
         "--output", os.path.basename(out), "--output-dir", os.path.dirname(out),
         path],
        capture_output=True, text=True, timeout=timeout,
    )
    if r.returncode != 0 or not os.path.isfile(out):
        return False, (r.stdout + r.stderr)[-400:]
    try:
        with open(out) as f:
            nb = json.load(f)
        return True, cell_text(nb)
    except Exception as exc:
        return False, str(exc)


# ---- execute deliverable /app/setup_r_env.sh (idempotent) ----
if not os.path.isfile(SETUP):
    probs.append("setup_script_missing <%s>" % SETUP)
else:
    t0 = __import__("time").time()
    r = subprocess.run(["bash", SETUP], capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        probs.append("setup_r_env_exit %d <%s>" % (r.returncode, r.stderr[-300:]))
    if __import__("time").time() - t0 > 200:
        probs.append("setup_r_env_not_idempotent (re-run took >200s)")

if no_modify_broken:
    probs.append("visible inputs modified or missing (no-modify rule)")

# ---- kernelspec state: causalr present and correct, r_old gone ----
ks = "/root/.local/share/jupyter/kernels/causalr/kernel.json"
argv0 = ""
display = ""
if os.path.isfile(ks):
    try:
        kd = json.load(open(ks))
        argv0 = (kd.get("argv") or [""])[0]
        display = kd.get("display_name") or ""
    except Exception as exc:
        probs.append("causalr_kernel_json_unreadable <%s>" % exc)
else:
    probs.append("causalr_kernel_json_missing <%s>" % ks)
check("causalr_argv_executable", bool(argv0) and os.path.isfile(argv0)
      and os.access(argv0, os.X_OK), argv0)
check("causalr_display_name", display == "Causal Lab R", display)
kl = subprocess.run(["jupyter", "kernelspec", "list"], capture_output=True, text=True)
check("causalr_listed", "causalr" in kl.stdout, kl.stdout + kl.stderr)
check("r_old_gone", not os.path.exists("/root/.local/share/jupyter/kernels/r_old"))

# ---- R packages loadable ----
jr = subprocess.run(["Rscript", "--vanilla", "-e",
                     'cat(requireNamespace("IRkernel", quietly=TRUE))'],
                    capture_output=True, text=True)
check("r_irkernel_pkg", jr.stdout.strip() == "TRUE", jr.stdout + jr.stderr)
jl = subprocess.run(["Rscript", "--vanilla", "-e",
                     'suppressMessages(library(jsonlite)); cat("JL_READY")'],
                    capture_output=True, text=True)
check("r_jsonlite_pkg", jl.returncode == 0 and "JL_READY" in jl.stdout,
      jl.stdout + jl.stderr)

# ---- deliverable /app/analysis/causal_probe.executed.ipynb ----
if not os.path.isfile(EXECUTED_NB):
    probs.append("executed_notebook_missing <%s>" % EXECUTED_NB)
else:
    try:
        with open(EXECUTED_NB) as f:
            nb = json.load(f)
        check("executed_nb_format", nb.get("nbformat") == 4)
        code_cells = [c for c in nb.get("cells", []) if c.get("cell_type") == "code"]
        check("executed_nb_run", code_cells
              and all(c.get("execution_count") is not None for c in code_cells))
        txt = cell_text(nb)
        for m in VISIBLE_MARKERS:
            check("executed_nb_marker %r" % m, m in txt)
    except Exception as exc:
        probs.append("executed_notebook_unreadable <%s>" % exc)

# ---- visible case: execute pristine probe via the causalr kernel ----
ok, txt = exec_markers(VISIBLE_NB)
check("visible_probe_executes", ok, txt)
if ok:
    for m in VISIBLE_MARKERS:
        check("visible_marker %r" % m, m in txt, txt[:300])

# ---- hidden R probe notebooks ----
hd = "/tests/hidden"
if os.path.isdir(hd):
    cases = sorted(d for d in os.listdir(hd)
                   if os.path.isdir(os.path.join(hd, d)))
    if not cases:
        probs.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hd, c)
        nb_path = os.path.join(base, "probe.ipynb")
        exp_path = os.path.join(base, "expected.json")
        if not (os.path.isfile(nb_path) and os.path.isfile(exp_path)):
            probs.append("hidden '%s' malformed" % c)
            continue
        try:
            with open(exp_path) as f:
                exp = json.load(f)
        except Exception as exc:
            probs.append("hidden '%s' expected unreadable <%s>" % (c, exc))
            continue
        ok, txt = exec_markers(nb_path)
        check("hidden '%s' executes" % c, ok, txt)
        if ok:
            for m in exp.get("markers", []):
                check("hidden '%s' marker %r" % (c, m), m in txt, txt[:300])
else:
    probs.append("hidden dir missing")

print("verify failures:", probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
