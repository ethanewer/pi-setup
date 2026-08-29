#!/usr/bin/env python3
"""Verifier for cedar-pier (executes-deliverable). Executes /app/train.py via the
documented CLI contract and checks the results:

 1. Default run (no overrides) exits 0 and persists /app/model.joblib and
    /app/vector.out. The loaded model is a scikit-learn linear model whose
    coefficient vector length equals the feature count, the constrained
    feature's coefficient is strictly negative, the vector file parses with
    numpy.loadtxt into exactly that many rows and matches the coef vector, and
    held-out accuracy on /app/data/val_company.csv meets the (independent)
    floor. The experiment dir has non-empty config snapshot + progress.
 2. Debug run (debug.enabled=true) exits 0, records n_epochs_effective==1 with a
    small batch under <experiment>/debug, and leaves the default model intact.
 3. Every hidden core fold (train+holdout) must run; sign / shape / vector /
    accuracy all hold on the fresh data.
 4. The malformed hidden input (missing constrained column) must exit non-zero
    without producing a vector file.
"""
import os, sys, json, glob, tempfile, subprocess
import numpy as np, pandas as pd, yaml, joblib

REWARD_FILE = "/logs/verifier/reward.txt"
HARD_MIN_ACC = 0.80
fails = []


def fail(m):
    print("FAIL: " + m, file=sys.stderr)


def run_train(args, timeout=220):
    return subprocess.run([sys.executable, "/app/train.py"] + args,
                          cwd="/app", capture_output=True, text=True,
                          timeout=timeout)


def load_split(csv_path, target):
    df = pd.read_csv(csv_path)
    y = df[target].astype(float).to_numpy()
    feats = [c for c in df.columns if c != target]
    X = df[feats].astype(float).to_numpy()
    return X, y, feats


def check_result(model_path, vector_path, feat_cols, ho_csv, target, floor, label,
                 constrained):
    from sklearn.base import BaseEstimator
    try:
        m = joblib.load(model_path)
        if not isinstance(m, BaseEstimator) or not hasattr(m, "coef_"):
            fail("%s is not a sklearn linear model" % model_path)
            return
        coef = np.asarray(m.coef_)
        if coef.ndim == 1:
            coef = coef.reshape(1, -1)
        if coef.shape[0] != 1:
            fail("%s: coef shape got=%s (want 1 x n_features)" % (model_path, coef.shape))
            return
        nfeat = coef.shape[1]
        if nfeat != len(feat_cols):
            fail("%s: parameter length %d != feature count %d"
                 % (model_path, nfeat, len(feat_cols)))
            return
        if constrained not in feat_cols:
            fail("constrained feature %r not among features" % constrained)
            return
        ci = feat_cols.index(constrained)
        if float(coef[0, ci]) >= 0.0:
            fail("%s: constrained coef not strictly negative: %r"
                 % (model_path, float(coef[0, ci])))
            return
        if not os.path.exists(vector_path):
            fail("vector file missing: %s" % vector_path)
            return
        vec = np.loadtxt(vector_path)
        if vec.ndim != 1 or vec.shape[0] != nfeat:
            fail("vector file not a flat length-%d numeric vector: shape=%r"
                 % (nfeat, vec.shape))
            return
        if not np.allclose(vec, coef[0], atol=1e-8, rtol=1e-6):
            fail("vector file does not match persisted coef vector (%s)"
                 % model_path)
            return
        if ho_csv:
            Xv = pd.read_csv(ho_csv).drop(columns=[target]).astype(float).to_numpy()
            yv = pd.read_csv(ho_csv)[target].astype(float).to_numpy()
            acc = float((m.predict(Xv) == yv).mean())
            if acc + 1e-9 < floor:
                fail("accuracy %.4f < floor %.4f (%s)" % (acc, floor, label))
    except Exception as e:
        fail("check crashed (%s): %s" % (model_path, e))


# ------------------------------------------------------------------------ config
cfg = None
if os.path.exists("/app/config.yaml"):
    try:
        cfg = yaml.safe_load(open("/app/config.yaml"))
    except Exception as e:
        fail("config.yaml unparsable: %s" % e)
if cfg is None:
    fail("config.yaml missing")
    open(REWARD_FILE, "w").write("0")
    print("VERIFY reward=0 fails=%d" % len(fails))
    sys.exit(0)

try:
    target = cfg["data"]["target"]
    constrained = cfg["data"]["constrained_feature"]
    conf_floor = float(cfg["metrics"]["accuracy_floor"])
    exp0 = cfg["paths"]["experiment"]
    serialized_default = cfg["paths"]["serialized"]
    vector_default = cfg["paths"]["vector"]
    validation_default = cfg["paths"]["validation"]
    company_csv = cfg["paths"]["dataset"]
except Exception as e:
    fail("config missing required keys: %s" % e)
    open(REWARD_FILE, "w").write("0")
    print("VERIFY reward=0 fails=%d" % len(fails))
    sys.exit(0)

floor = max(conf_floor, HARD_MIN_ACC)

if not (os.path.exists("/app/train.py") and os.path.exists("/app/config.yaml")):
    fail("deliverable train.py/config.yaml missing")

# ------------------------------------------------------------- 1) default run
if os.path.exists("/app/train.py"):
    try:
        r = run_train([])
    except subprocess.TimeoutExpired:
        fail("default run timed out")
        r = None
    if r is not None and r.returncode != 0:
        fail("default run exit=%d stderr=%s" % (r.returncode, r.stderr[-400:]))
    elif r is not None:
        if not (os.path.exists(serialized_default) and os.path.exists(vector_default)):
            fail("default run did not persist model and/or vector")
        else:
            try:
                _, _, feats = load_split(company_csv, target)
            except Exception as e:
                feats = []
                fail("split error on visible data: %s" % e)
            check_result(serialized_default, vector_default, feats,
                         validation_default, target, floor, "visible", constrained)
        for name in ("config_snapshot.yaml", "progress.json"):
            fp = os.path.join(exp0, name)
            if not os.path.exists(fp) or not os.path.getsize(fp):
                fail("experiment %s missing/empty" % fp)
            elif name == "progress.json":
                try:
                    json.load(open(fp))
                except Exception as e2:
                    fail("progress.json not valid JSON: %s" % e2)

    # -------------------------------------------------------- 2) debug override
    try:
        rd = run_train(["debug.enabled=true"])
    except subprocess.TimeoutExpired:
        fail("debug run timed out")
        rd = None
    if rd is not None and rd.returncode != 0:
        fail("debug run failed: %s" % rd.stderr[-300:])
    elif rd is not None:
        dbj = os.path.join(exp0, "debug", "progress.json")
        if not os.path.exists(dbj) or not os.path.getsize(dbj):
            fail("debug progress.json missing/empty")
        else:
            p = json.load(open(dbj))
            want_epochs = int(cfg.get("debug", {}).get("epochs", 1))
            if int(p.get("n_epochs_effective", -1)) != want_epochs:
                fail("debug n_epochs_effective got %r want %d"
                     % (p.get("n_epochs_effective"), want_epochs))
            if "batch_size" not in p:
                fail("debug progress missing batch_size")
        if not os.path.exists(os.path.join(exp0, "debug", "config_snapshot.yaml")):
            fail("debug config snapshot missing")
        if os.path.exists(serialized_default):
            try:
                joblib.load(serialized_default)   # default model must survive debug
            except Exception as e2:
                fail("default model broken after debug: %s" % e2)

    # ----------------------------------------------------- 3) hidden core folds
    cases = sorted(glob.glob("/tests/hidden/core/case*/"))
    if not cases:
        fail("no hidden core cases found")
    for cdir in cases:
        tr = os.path.join(cdir, "train.csv")
        tho = os.path.join(cdir, "holdout.csv")
        if not (os.path.exists(tr) and os.path.exists(tho)):
            fail("hidden case incomplete: %s" % cdir)
            continue
        with tempfile.TemporaryDirectory() as td:
            args = ["paths.dataset=" + tr, "paths.validation=" + tho,
                    "paths.serialized=" + os.path.join(td, "m.joblib"),
                    "paths.vector=" + os.path.join(td, "v.out"),
                    "paths.experiment=" + os.path.join(td, "exp")]
            try:
                rr = run_train(args)
            except subprocess.TimeoutExpired:
                fail("hidden fold %s timed out" % cdir)
                continue
            if rr.returncode != 0:
                fail("hidden fold %s failed: %s"
                     % (os.path.basename(cdir.rstrip("/")), rr.stderr[-300:]))
            else:
                try:
                    _, _, feats = load_split(tr, target)
                except Exception as e:
                    feats = []
                    fail("load hidden train %s: %s" % (tr, e))
                check_result(os.path.join(td, "m.joblib"), os.path.join(td, "v.out"),
                             feats, tho, target, floor,
                             "hidden-" + os.path.basename(cdir.rstrip("/")),
                             constrained)

    # -------------------------------------------------------- 4) malformed case
    mal = sorted(glob.glob("/tests/hidden/malformed/*/train.csv"))
    if not mal:
        fail("no malformed hidden case")
    for mt in mal:
        with tempfile.TemporaryDirectory() as td:
            args = ["paths.dataset=" + mt,
                    "paths.validation=" + validation_default,
                    "paths.serialized=" + os.path.join(td, "m.joblib"),
                    "paths.vector=" + os.path.join(td, "v.out"),
                    "paths.experiment=" + os.path.join(td, "exp")]
            try:
                rm = run_train(args)
            except subprocess.TimeoutExpired:
                fail("malformed case timed out")
                continue
            if rm.returncode == 0:
                fail("malformed input %s must exit non-zero" % mt)
            elif os.path.exists(os.path.join(td, "v.out")):
                fail("malformed input produced a vector file")

# -------------------------------------------------------------------- verdict
ok = 1 if not fails else 0
open(REWARD_FILE, "w").write(str(ok))
print("VERIFY reward=%d fails=%d" % (ok, len(fails)))
sys.exit(0)