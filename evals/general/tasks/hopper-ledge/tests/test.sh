#!/bin/bash
# hopper-ledge verifier (executes-deliverable).
#
# Repairs are graded on the observed pipeline:
#   * the visible repo must go green on a COLD run (fresh work root, empty
#     cache) and again on a WARM run (fresh work root, same cache), with the
#     install step done on run 1 and skipped on run 2 and the cache hit
#     on run 2 — proving the dependency cache is saved completely and its key
#     is stable;
#   * the artifact gate (verify_artifact) and the full test suite must run on
#     every run, and the shipped test files must be byte-identical to the
#     pristine suite (no skipped, filtered, weakened or deleted assertions);
#   * the same runner must pass the same two-run contract on three hidden
#     fixture repositories with different job names, artifact dirs, cache
#     paths, lockfiles and topologies.
# Writes exactly 0 or 1 to /logs/verifier/reward.txt on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if [ ! -f /app/repo/ci/runner.py ] || [ ! -f /app/repo/ci/pipeline.json ]; then
  echo "FAIL: deliverable /app/repo missing its CI pipeline" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path("/app/repo")
RUNNER = REPO / "ci" / "runner.py"

failures = []


def fail(msg):
    failures.append(msg)


def check(cond, msg):
    if not cond:
        fail(msg)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def run_pipeline(pipeline, repo, work, cache, summary, timeout=400):
    r = subprocess.run(
        [sys.executable, str(RUNNER), "--pipeline", str(pipeline),
         "--repo", str(repo), "--work-root", str(work),
         "--cache-dir", str(cache), "--summary", str(summary)],
        capture_output=True, text=True, timeout=timeout)
    return r


def load_summary(path):
    try:
        return json.loads(Path(path).read_text())
    except Exception:
        return None


def find_steps(summary, name):
    """All (job, status, output) records for steps named NAME."""
    out = []
    for job, j in (summary or {}).get("jobs", {}).items():
        for st in j.get("steps", []):
            if st.get("name") == name:
                out.append((job, st.get("status"), st.get("output")))
    return out


def cache_events(summary):
    events = []
    for j in (summary or {}).get("jobs", {}).values():
        events.extend(e for e in j.get("cache", []))
    return events


def collect_count(repo_dir):
    """Number of pytest items collected in the repo working tree."""
    r = subprocess.run(
        [sys.executable, "-m", "pytest", "-p", "no:cacheprovider",
         "--collect-only", "-q", "tests/"],
        cwd=str(repo_dir), capture_output=True, text=True, timeout=240)
    n = 0
    for line in r.stdout.splitlines():
        if "::" in line:
            n += 1
    return n if r.returncode == 0 else -1


SKIP_RE = re.compile(
    r"@pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\s*\(|@unittest\.skip|"
    r"\bxfail\b|--deselect|pytest\.mark\.skip")


def check_suite_intact(label, test_dir, manifest):
    """Test files byte-identical to the pristine manifest, no skip markers."""
    # Manifest keys are repository-relative ("tests/test_core.py"); collapse
    # them to names relative to the tests dir for the on-disk comparison.
    expected = {k.split("/", 1)[-1]: v
                for k, v in manifest.get("test_files", {}).items()}
    on_disk = {}
    for p in sorted(Path(test_dir).rglob("*.py")):
        rel = p.relative_to(test_dir).as_posix()
        on_disk[rel] = sha(p)
    if on_disk != expected:
        missing = sorted(set(expected) - set(on_disk))
        extra = sorted(set(on_disk) - set(expected))
        changed = sorted(r for r in set(expected) & set(on_disk)
                         if expected[r] != on_disk[r])
        fail("%s: test suite changed (missing=%s extra=%s changed=%s)"
             % (label, missing, extra, changed))
    for p in sorted(Path(test_dir).rglob("*.py")):
        text = p.read_text(errors="replace")
        hits = [m for m in SKIP_RE.findall(text) if m]
        if hits:
            fail("%s: test file %s contains skip/deselect markers: %s"
                 % (label, p.name, sorted(set(hits))))


def check_pipeline_not_rigged(label, pipeline_text, script_dir):
    for pat in ("--deselect", "pytest.skip(", "-k "):
        if pat in pipeline_text:
            fail("%s: pipeline definition filters or skips tests (%r)"
                 % (label, pat))
    for p in sorted(Path(script_dir).rglob("*.py")):
        text = p.read_text(errors="replace")
        for pat in ("pytest.skip(", "--deselect"):
            if pat in text:
                fail("%s: %s filters or skips tests (%r)"
                     % (label, p.name, pat))


def two_run(label, pipeline, repo_dir, manifest):
    """Run the pipeline cold then warm; assert the whole contract."""
    base = Path(tempfile.mkdtemp(prefix="hopper-verify-"))
    work, cache = base / "work", base / "cache"
    s1, s2 = base / "summary1.json", base / "summary2.json"

    r1 = run_pipeline(pipeline, repo_dir, work, cache, s1)
    sum1 = load_summary(s1)
    if r1.returncode != 0 or not sum1 or sum1.get("result") != "success":
        tail = (r1.stdout + r1.stderr).strip().splitlines()
        fail("%s: cold run was not green (exit=%s, result=%s); log tail: %s"
             % (label, r1.returncode,
                (sum1 or {}).get("result"),
                " | ".join(tail[-4:])))
        return

    ev1 = cache_events(sum1)
    if not ev1 or not any(not e.get("hit") for e in ev1):
        fail("%s: cold run recorded no cache miss" % label)
    install1 = find_steps(sum1, "install")
    if not install1 or any(st != "done" for _, st, _ in install1):
        fail("%s: install step must run (done) on the cold run; got %r"
             % (label, [(n, st) for n, st, _ in install1]))
    verify1 = find_steps(sum1, "verify_artifact")
    if not verify1 or any(st != "done" for _, st, _ in verify1):
        fail("%s: artifact gate (verify_artifact) did not pass on the cold run"
             % label)
    unit1 = find_steps(sum1, "unit")
    want1 = manifest["tests_passed"]
    if not unit1 or any(st != "done" for _, st, _ in unit1) \
            or sum1.get("tests", {}).get("passed") != want1:
        fail("%s: full test suite did not run and pass on the cold run "
             "(tests=%r want %d)" % (label, (sum1 or {}).get("tests"), want1))

    # Warm run: fresh work root, same cache.
    shutil.rmtree(work, ignore_errors=True)
    r2 = run_pipeline(pipeline, repo_dir, work, cache, s2)
    sum2 = load_summary(s2)
    if r2.returncode != 0 or not sum2 or sum2.get("result") != "success":
        tail = (r2.stdout + r2.stderr).strip().splitlines()
        fail("%s: warm run was not green (exit=%s, result=%s); log tail: %s"
             % (label, r2.returncode, (sum2 or {}).get("result"),
                " | ".join(tail[-4:])))
        return
    ev2 = cache_events(sum2)
    if not ev2 or not any(e.get("hit") for e in ev2):
        fail("%s: warm run did not hit the dependency cache" % label)
    keys1 = {e.get("key") for e in ev1}
    keys2 = {e.get("key") for e in ev2}
    if not keys1 or keys1 != keys2:
        fail("%s: cache keys differ between runs (%s vs %s)" % (label, keys1, keys2))
    install2 = find_steps(sum2, "install")
    if not install2 or any(st != "skipped" for _, st, _ in install2):
        fail("%s: install step must be skipped on the warm run; got %r"
             % (label, [(n, st) for n, st, _ in install2]))
    verify2 = find_steps(sum2, "verify_artifact")
    if not verify2 or any(st != "done" for _, st, _ in verify2):
        fail("%s: artifact gate did not pass on the warm run" % label)
    unit2 = find_steps(sum2, "unit")
    if not unit2 or any(st != "done" for _, st, _ in unit2) \
            or sum2.get("tests", {}).get("passed") != want1:
        fail("%s: full test suite did not run and pass on the warm run "
             "(tests=%r want %d)" % (label, (sum2 or {}).get("tests"), want1))

    # Real-content checks: a fabricated summary (no actual work) cannot
    # produce a real dependency snapshot or a tangible build artifact, so
    # verify the cache and artifact stores hold the actual pipeline output:
    # the cache tar must contain the DEPENDENCIES manifest the install step
    # wrote plus the vendored package files it copied, and the artifact
    # store must contain the actual wheel/bundle files the build emitted.
    import tarfile
    import zipfile

    def _dep_name(content):
        m = re.match(r"([A-Za-z0-9_.+-]+)==(\d[A-Za-z0-9_.+-]*)\s*$",
                     content.decode("utf-8", "replace").strip())
        return m.group(1) if m else None

    tarballs = list(Path(cache).glob("*.tar.gz"))
    check(any(tarballs),
          "%s: no dependency cache snapshot was written" % label)
    dep_ok = False
    for tb in tarballs:
        try:
            with tarfile.open(str(tb), "r:gz") as tf:
                members = [m for m in tf.getmembers() if m.isfile()]
                dep = None
                for m in members:
                    if Path(m.name).name == "DEPENDENCIES":
                        dep = _dep_name(tf.extractfile(m).read())
                        break
                depdirs = {Path(m.name).parent.name for m in members}
            if dep and dep in depdirs and len(members) >= 2:
                dep_ok = True
                break
        except Exception:
            continue
    check(dep_ok,
          "%s: cached dependency snapshot is not real install output "
          "(DEPENDENCIES manifest or vendored files missing)" % label)
    art_root = Path(cache) / "artifacts"
    artfiles = [f for f in art_root.rglob("*")
                if f.is_file() and f.name != ".team-artifacts.json"]

    def _zip_names(p):
        with zipfile.ZipFile(str(p)) as zf:
            return set(zf.namelist())

    build_art_ok = False
    for f in artfiles:
        if f.suffix != ".json":
            continue
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        if not isinstance(data, dict) or data.get("package") not in (
                "ledger", "wigeon", "curlew", "avocet"):
            continue
        good = True
        if "wheel" in data:
            wf = f.parent / str(data["wheel"])
            if not wf.is_file():
                good = False
            else:
                try:
                    names = _zip_names(wf)
                except Exception:
                    names = set()
                if not (any(Path(n).name == "VERSION" for n in names)
                        and any(n.endswith(".py") for n in names)):
                    good = False
        if "bundle" in data:
            bf = f.parent / str(data["bundle"])
            if not bf.is_file():
                good = False
            else:
                try:
                    names = _zip_names(bf)
                except Exception:
                    names = set()
                if not any(n.endswith(".whl") for n in names):
                    good = False
        if good:
            build_art_ok = True
            break
    check(build_art_ok,
          "%s: no real build artifact (wheel/bundle) in the artifact store"
          % label)


# ---------------------------------------------------------------------------
# 0. deliverable sanity
# ---------------------------------------------------------------------------
check(RUNNER.is_file() and (REPO / "ci" / "pipeline.json").is_file(),
      "missing /app/repo deliverable files")
if RUNNER.is_file():
    run_text = RUNNER.read_text(errors="replace")
    for pat in ("pytest.skip(", "--deselect", "xfail"):
        if pat in run_text:
            fail("runner itself contains skip/filter machinery (%r)" % pat)

# ---------------------------------------------------------------------------
# 1. visible repo: suite integrity + rigged-pipeline scan
# ---------------------------------------------------------------------------
vis_manifest = json.loads(Path("/tests/suite_manifest.json").read_text())
check_suite_intact("visible", REPO / "tests", vis_manifest)
check_pipeline_not_rigged("visible",
                          (REPO / "ci" / "pipeline.json").read_text(),
                          REPO / "scripts")
cnt = collect_count(REPO)
check(cnt == vis_manifest["tests_passed"],
      "visible: pytest collects %d tests, expected %d"
      % (cnt, vis_manifest["tests_passed"]))

# Clear any scratch build output the agent left at the repo root, then prove
# the fixed pipeline never writes into the checkout.
for name in ("dist", ".deps", ".vendor", "build", "release", "out",
             "artifacts", ".cache_deps"):
    p = REPO / name
    if p.exists():
        shutil.rmtree(p, ignore_errors=True)

two_run("visible", REPO / "ci" / "pipeline.json", REPO, vis_manifest)

for name in ("dist", ".deps", ".vendor", "build", "release", "out",
             "artifacts", ".cache_deps"):
    check(not (REPO / name).exists(),
          "checkout hygiene: %s must not appear in /app/repo after runs"
          % name)

# ---------------------------------------------------------------------------
# 2. hidden fixture repositories: same runner, same two-run contract
# ---------------------------------------------------------------------------
HIDDEN_EXPECT = {
    "wigeon": {
        "tests_passed": 16,
        "test_files": {
            "tests/test_core.py":
                "4da851e64f3a6295ae4253e34c4e3880f7e7a49f3ecebf42a53e58f019fb85f2",
            "tests/test_repo_hygiene.py":
                "d6b5763b4f63cf37b24cee921e81e80f7eb627533d608e7f9bc7493b8ec5c7ea",
        },
    },
    "curlew": {
        "tests_passed": 12,
        "test_files": {
            "tests/test_core.py":
                "d270ba3fa74eeb5f707c094496c1b8b21ee5d6a8c1690b5215bf2d8eff3099d2",
            "tests/test_repo_hygiene.py":
                "3f33c09436f017c348d6f89a911b05f6ac98f78de46249f3ad50b749f03ca291",
        },
    },
    "avocet": {
        "tests_passed": 14,
        "test_files": {
            "tests/test_core.py":
                "381dffe3921e2ef672bf2da5a314b4a514d7772ce6589bc223adb7c3a3580cfe",
            "tests/test_repo_hygiene.py":
                "b09a71bde081b1b33289b4f0c8f53dae405e5fc6d4878d4e3f369d7da7624db3",
        },
    },
}

hidden_root = Path("/tests/hidden")
cases = sorted(d.name for d in hidden_root.iterdir()
               if d.is_dir() and d.name in HIDDEN_EXPECT)
check(len(cases) >= 2, "expected at least 2 hidden cases, found %s" % cases)
for case in cases:
    manifest = HIDDEN_EXPECT[case]
    fx = hidden_root / case / "repo"
    check((fx / "ci" / "pipeline.json").is_file(),
          "%s: hidden fixture pipeline missing" % case)
    check_suite_intact(case, fx / "tests", manifest)
    check_pipeline_not_rigged(case,
                              (fx / "ci" / "pipeline.json").read_text(),
                              fx / "scripts")
    two_run(case, fx / "ci" / "pipeline.json", fx, manifest)

# ---------------------------------------------------------------------------
if failures:
    print("FAILURES (%d):" % len(failures))
    for m in failures:
        print("  - " + m)
    Path("/logs/verifier/reward.txt").write_text("0")
    sys.exit(0)

print("ALL PASS: visible + %d hidden fixtures green on cold and warm runs; "
      "suites byte-identical; artifact gate intact" % len(cases))
Path("/logs/verifier/reward.txt").write_text("1")
sys.exit(0)
PY