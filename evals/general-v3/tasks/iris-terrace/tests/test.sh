#!/bin/bash
# iris-terrace verifier (executes-deliverable).
# 1. requires the four /app deliverables to exist;
# 2. visible checks (embedded python): re-runs the fitter on /app/spectrum.csv
#    and verifies /app/fit_results.json is a consistent, valid, sorted fit;
#    rebuilds the visible stacked model, computes the separability matrix by an
#    independent numerical-Jacobian method and checks BOTH the committed
#    /app/stack_result.json AND /app/stack_models.separability_matrix agree;
#    independently computes sqrt-wasserstein on the documented example and
#    checks /app/wasserstein.py returns the rooted distance.
# 3. runs every hidden case driver under /tests/hidden/*/run.py.
# All pass -> REWARD=1; any failure -> REWARD=0.
set -u
mkdir -p /logs/verifier
R=1
fail() { echo "FAIL: $1" >&2; R=0; }

for f in /app/fit_spectra.py /app/fit_results.json /app/stack_models.py /app/wasserstein.py; do
  [ -f "$f" ] || fail "missing deliverable $f"
done

if [ "$R" = 1 ]; then
  python3 - <<'PY' || FAIL_VIS=1
import json, os, subprocess, sys
import numpy as np

errs = []

# ---------------- visible: spectral fit ----------------
res = json.load(open("/app/fit_results.json"))
peaks = res.get("peaks")
if not isinstance(peaks, list) or len(peaks) < 1:
    errs.append("fit_results.json has no peaks list")
else:
    keys = {"center", "width", "amplitude", "offset"}
    for p in peaks:
        if not keys.issubset(p.keys()):
            errs.append("peak missing keys"); break
    cs = [p["center"] for p in peaks]
    if cs != sorted(cs):
        errs.append("peaks not sorted by center")
    if any(p["width"] <= 0 or p["amplitude"] < 0 for p in peaks):
        errs.append("negative width/amplitude")

# re-run the fitter on the visible fixture and compare consistency
vis = "/tmp/vis_fit.json"
if os.path.exists(vis):
    os.remove(vis)
r = subprocess.run([sys.executable, "/app/fit_spectra.py", "/app/spectrum.csv", "--out", vis],
                   capture_output=True, text=True)
if r.returncode != 0:
    errs.append("fitter exited %d: %s" % (r.returncode, r.stderr[-400:]))
else:
    re_fits = json.load(open(vis))["peaks"]
    if len(re_fits) != len(peaks):
        errs.append("re-run peak count differs")
    else:
        for a, b in zip(peaks, re_fits):
            if abs(a["center"] - b["center"]) > 2e-2 or \
               abs(a["width"] - b["width"]) > 0.05 or \
               abs(a["amplitude"] - b["amplitude"]) > 0.3 or \
               abs(a["offset"] - b["offset"]) > 0.3:
                errs.append("committed fit diverges from re-run")
                break

# ---------------- visible: separability ----------------
sys.path.insert(0, "/app")
try:
    from astropy.modeling.models import Linear1D, Mapping
    import stack_models

    vis_model = (Linear1D(1.0, 0.0) & Linear1D(2.0, 0.0)) & Mapping((1, 0))

    def num_sep(model):
        n = model.n_inputs
        arr = np.linspace(0.7, 2.3, n) if n > 1 else np.array([1.3])
        y0 = model(*arr) if n > 1 else model(arr[0])
        if not isinstance(y0, (tuple, list)):
            y0 = (y0,)
        y0 = np.asarray(y0, dtype=float)
        Rm = np.zeros((model.n_outputs, n), dtype=int)
        for i in range(n):
            xp = list(arr); xp[i] += 1e-3
            yp = model(*xp) if n > 1 else model(xp[0])
            if not isinstance(yp, (tuple, list)):
                yp = (yp,)
            yp = np.asarray(yp, dtype=float)
            for o in range(model.n_outputs):
                if abs(yp[o] - y0[o]) > 2e-6:
                    Rm[o, i] = 1
        return Rm

    ref = num_sep(vis_model)
    got_mod = np.asarray(stack_models.separability_matrix(vis_model), dtype=int)
    if got_mod.shape != ref.shape or not (got_mod == ref).all():
        errs.append("stack_models.separability_matrix mismatch on visible model")
    if os.path.exists("/app/stack_result.json"):
        sj = json.load(open("/app/stack_result.json"))
        gotj = np.asarray(sj["separability"], dtype=int)
        if gotj.shape != ref.shape or not (gotj == ref).all():
            errs.append("/app/stack_result.json mismatch on visible model")
except Exception as exc:  # noqa: BLE001
    errs.append("separability visible check raised %r" % (exc,))

# ---------------- visible: wasserstein ----------------
try:
    from wasserstein import sqrt_wasserstein
    d = sqrt_wasserstein([[0.3, 0.2], [0.2, 0.3]], [[1.0, 4.0], [4.0, 1.0]])
    if abs(d - float(np.sqrt(2.2))) > 1e-9:
        errs.append("wasserstein not the rooted distance: %r" % (d,))
except Exception as exc:  # noqa: BLE001
    errs.append("wasserstein visible check raised %r" % (exc,))

if errs:
    for e in errs:
        print("FAIL: visible:", e, file=sys.stderr)
    sys.exit(1)
print("visible checks ok")
PY
  rc=$?
  if [ "${FAIL_VIS:-0}" = 1 ] || [ "$rc" != 0 ]; then fail "visible checks"; fi
  unset FAIL_VIS
fi

# ---------------- hidden cases ----------------
if [ "$R" = 1 ]; then
  for d in /tests/hidden/*/; do
    [ -d "$d" ] || continue
    drv="$d"run.py
    [ -f "$drv" ] || continue
    if python3 "$drv" >/tmp/hc_out.txt 2>&1; then
      echo "hidden/$(basename "$d"): $(tail -n1 /tmp/hc_out.txt)"
    else
      echo "hidden/$(basename "$d"): FAILED"
      sed 's/^/    /' /tmp/hc_out.txt | tail -3 >&2
      fail "hidden/$(basename "$d")"
    fi
  done
fi

echo "REWARD=$R"
echo "$R" > /logs/verifier/reward.txt
exit 0
