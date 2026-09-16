#!/usr/bin/env python3
"""Generate the hopper-ledge fixture repository at <out>/repo.

Builds a self-contained org repository (readme, source library, pytest
suite, build + artifact-gate scripts, vendored dependency, and a local CI
runner with its pipeline definition) and commits it incrementally so the
result ships with a real git history. The pipeline is red: the shared
runner at ci/runner.py carries three independent defects (artifact
downloads land under a nested dir instead of the consumer workspace root;
a dependency cache is snapshotted at restore time, before the install
step has populated it, so the warm run restores an empty cache and skips
the install; all jobs share a single workspace checkout, so build output
leaks into the test job and trips the repo hygiene test). Every job and
every test passes in isolation; the failures only appear when the
pipeline runs as a whole, twice in a row.

Usage: python3 gen_repo.py <out-dir>
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "repo"
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)

GIT = ["git", "-C", str(OUT)]
AUTH = {
    "GIT_AUTHOR_NAME": "build",
    "GIT_AUTHOR_EMAIL": "build@localhost",
    "GIT_COMMITTER_NAME": "build",
    "GIT_COMMITTER_EMAIL": "build@localhost",
}


def write(rel, text):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def commit(msg):
    env = dict(os.environ)
    env.update(AUTH)
    subprocess.run(GIT + ["add", "-A"], check=True, env=env)
    subprocess.run(GIT + ["commit", "-q", "-m", msg], check=True, env=env)


# --------------------------------------------------------------------------
# The BUGGY local CI runner. Three independent defects, each in its own
# function, none of them visible when a single job or step runs alone:
#
#   * download_artifacts materialises the exported files under
#     <workspace>/artifacts/<job>/ instead of the consumer workspace root,
#     so the very next step cannot find the files it depends on.
#   * restore_cache snapshots the cache path at restore time, when the
#     install step has not run yet; the warm second run restores that empty
#     snapshot, the (cache-gated) install step is skipped, and the build
#     fails with a missing dependency.
#   * all jobs run in one shared workspace checkout, so one job's generated
#     output sits in the tree when the next job's tests run, and the suite's
#     repo-hygiene test fails.
# --------------------------------------------------------------------------
BUGGY_RUNNER = r'''#!/usr/bin/env python3
"""team-ci runner: a small local CI that executes ci/pipeline.json.

This runner is shared by several repositories in the org. It:

  * parses a pipeline JSON (jobs with `needs:` and steps),
  * checks out the named repository into a throwaway workspace,
  * runs each job's steps in that workspace with an isolated shell,
  * exchanges files between jobs through an artifact store under the cache
    dir (a manifest of exported relative paths, re-materialised for the
    consumer job),
  * keeps a dependency cache keyed on the content of the lockfile named in
    the step's `key` template, e.g. `deps-{{hash:ci/deps.lock}}`,
  * writes a machine-readable summary JSON.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

IGNORED = frozenset({
    ".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".coverage",
    "dist", ".deps", ".vendor", "build", "release", "out", "artifacts",
})

# One shared checkout for every job in the pipeline.
_SHARED_CHECKOUT = None


def log(msg):
    print("[runner] " + msg, flush=True)


def log_err(msg):
    print("[runner] ERROR " + msg, flush=True)


def run_shell(cmd, cwd, env=None, timeout=300):
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    t0 = time.time()
    r = subprocess.run(cmd, shell=True, cwd=str(cwd), env=full_env,
                       capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + "\n" + r.stderr).strip(), time.time() - t0


def cache_key(spec, ws):
    """Expand a `prefix-{{hash:path}}` key to `prefix-<sha256(path)[:12]>`."""
    m = re.search(r"\{\{hash:([^}]+)\}\}", spec)
    if not m:
        return spec
    p = Path(ws) / m.group(1)
    data = p.read_bytes() if p.is_file() else b""
    digest = hashlib.sha256(data).hexdigest()[:12]
    return spec.replace(m.group(0), digest)


def fresh_workspace(repo_root, ws_root, job):
    ws = Path(ws_root) / job
    if ws.exists():
        shutil.rmtree(ws)
    ws.mkdir(parents=True, exist_ok=True)
    shutil.copytree(repo_root, ws, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(*IGNORED))
    return ws


def archive_cache(cache_dir, key, rel_path, ws):
    """Snapshot the cache path as <key>.tar.gz under the cache dir."""
    src = Path(ws) / rel_path
    tgt = Path(cache_dir) / (key + ".tar.gz")
    with tarfile.open(str(tgt), "w:gz") as tf:
        if src.exists():
            for f in src.rglob("*"):
                if f.is_file():
                    tf.add(str(f), arcname=(src.name + "/" +
                                            f.relative_to(src).as_posix()))
    return True


def restore_cache(cache_dir, key, ws):
    tgt = Path(cache_dir) / (key + ".tar.gz")
    if not tgt.exists():
        return False
    with tarfile.open(str(tgt), "r:gz") as tf:
        tf.extractall(str(ws))
    return True


def upload_artifacts(art_root, job, path, ws):
    src = Path(ws) / path
    if not src.is_dir():
        return None, "upload path not found: " + path
    dst = Path(art_root) / job
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)
    files = []
    for f in sorted(src.rglob("*")):
        if f.is_file():
            rel = f.relative_to(src).as_posix()
            parent = dst / Path(rel).parent
            parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(f), str(dst / rel))
            files.append(rel)
    (dst / ".team-artifacts.json").write_text(json.dumps({"files": files}))
    return files, None


def download_artifacts(art_root, job, dest):
    src = Path(art_root) / job
    if not src.exists():
        return None
    manifest = {"files": []}
    try:
        manifest = json.loads((src / ".team-artifacts.json").read_text())
    except Exception:
        pass
    files = []
    for rel in manifest.get("files", []):
        f = src / rel
        if f.is_file():
            out = Path(dest) / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(f), str(out))
            files.append(rel)
    return files


def add_step(steps, name, status, output=None):
    rec = {"name": name, "status": status}
    if output is not None:
        rec["output"] = output
    steps.append(rec)


def run_job(name, job_def, ws, art_root, cache_dir, env_base):
    steps = []
    cache_hit = False
    ok = True
    for idx, step in enumerate(job_def.get("steps", [])):
        stype = step.get("step")
        sname = step.get("name") or (stype or "step") + "#" + str(idx)
        cond = step.get("if", "always")
        if cond == "cache_miss" and cache_hit:
            add_step(steps, sname, "skipped")
            continue
        if cond == "cache_hit" and not cache_hit:
            add_step(steps, sname, "skipped")
            continue

        env = dict(env_base)
        env.update(step.get("env", {}))
        env["CACHE_HIT"] = "true" if cache_hit else "false"
        env["JOB"] = name
        out = ""
        status = "failed"
        try:
            if stype == "run":
                rc, out, _ = run_shell(step["cmd"], ws, env)
                status = "done" if rc == 0 else "failed"
            elif stype == "restore_cache":
                key = cache_key(step["key"], ws)
                hit = restore_cache(cache_dir, key, ws)
                if not hit:
                    # Snapshot now so a future run starts warm.
                    archive_cache(cache_dir, key, step["path"], ws)
                    out = "cache_miss key=" + key
                else:
                    out = "cache_hit key=" + key
                cache_hit = hit
                status = "done"
            elif stype == "upload_artifacts":
                files, err = upload_artifacts(art_root, name, step["path"], ws)
                if err is not None:
                    out, status = err, "failed"
                else:
                    out, status = "%d files" % len(files), "done"
            elif stype == "download_artifacts":
                froms = step.get("from")
                if not isinstance(froms, list):
                    froms = [froms]
                got = []
                status = "done"
                for j in froms:
                    # Exported files are materialised under artifacts/<job>/
                    # in this job's workspace.
                    files = download_artifacts(art_root, j,
                                               Path(ws) / "artifacts" / j)
                    if files is None:
                        out, status = "artifact missing: " + str(j), "failed"
                        break
                    got.extend(files)
                if status == "done":
                    out, status = "%d files" % len(got), "done"
            else:
                out, status = "unknown step type: " + str(stype), "failed"
        except subprocess.TimeoutExpired:
            out, status = "step timed out", "failed"
        except Exception as exc:  # pragma: no cover - defensive
            out, status = repr(exc), "failed"
        add_step(steps, sname, status, out)
        first = out.splitlines()[0] if out else ""
        log("job=%s step=%s status=%s %s" % (name, sname, status, first))
        if status != "done":
            ok = False
            break

    return {"status": "success" if ok else "failure",
            "steps": steps, "cache": []}


def topo_order(jobs):
    done, order = set(), []

    def visit(name, stack):
        if name in done:
            return True
        if name in stack:
            return False
        stack.add(name)
        for dep in jobs[name].get("needs", []):
            if dep not in jobs:
                return False
            if not visit(dep, stack):
                return False
        stack.discard(name)
        done.add(name)
        order.append(name)
        return True

    for name in jobs:
        if not visit(name, set()):
            return None
    return order


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pipeline", default=None,
                    help="path to pipeline.json (default <repo>/ci/pipeline.json)")
    ap.add_argument("--repo", default=None, help="repo checkout to run")
    ap.add_argument("--work-root", default="/tmp/team-ci/work")
    ap.add_argument("--cache-dir", default="/tmp/team-ci/cache")
    ap.add_argument("--summary", default="/tmp/team-ci/summary.json")
    args = ap.parse_args()

    global _SHARED_CHECKOUT
    repo_root = Path(args.repo or os.getcwd())
    pipeline_path = Path(args.pipeline or
                         (repo_root / "ci" / "pipeline.json"))
    try:
        pl = json.loads(pipeline_path.read_text())
    except Exception as exc:
        log_err("cannot read pipeline %s: %s" % (pipeline_path, exc))
        return 1
    jobs = pl.get("jobs", {})
    order = topo_order(jobs)
    if order is None:
        log_err("pipeline job graph has a cycle or an unknown need")
        return 1

    ws_root = Path(args.work_root)
    cache_dir = Path(args.cache_dir)
    ws_root.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)
    art_root = cache_dir / "artifacts"

    # One checkout for the whole run; every job works in it.
    _SHARED_CHECKOUT = fresh_workspace(repo_root, ws_root, "checkout")

    result, failed_job = "success", None
    job_results = {}
    total_tests = {"collected": None, "passed": None}
    for name in order:
        res = run_job(name, jobs[name], _SHARED_CHECKOUT, art_root,
                      cache_dir, {})
        job_results[name] = res
        if res["status"] != "success":
            result, failed_job = "failure", name
            break

    for res in job_results.values():
        for st in res.get("steps", []):
            if st.get("name") == "unit" and st.get("status") == "done":
                m = re.search(r"(\d+) passed", st.get("output", "") or "")
                if m:
                    total_tests = {"collected": int(m.group(1)),
                                   "passed": int(m.group(1))}

    summary = {"result": result, "failed_job": failed_job,
               "jobs": job_results, "tests": total_tests}
    out = Path(args.summary)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=2))
    log("result=%s failed_job=%s tests=%s" %
        (result, failed_job, total_tests.get("passed")))
    return 0 if result == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
'''


# --------------------------------------------------------------------------
# Repository content.
# --------------------------------------------------------------------------
README = """# ledger registry

Shared source for the ledger registry service: double-entry primitives in
`src/ledger`, built and gated by the org's local CI pipeline.

## Layout

    ci/runner.py          local CI runner (shared across org repositories)
    ci/pipeline.json      this repository's pipeline (jobs, steps, caches)
    ci/install.sh         installs the vendored dependency into .deps
    ci/deps.lock          dependency manifest (hashed for the cache key)
    ci/vendor/            vendored dependency source
    scripts/build.py      assembles dist/ledger.whl + sidecar metadata
    scripts/check_artifact.py  consumer-side gate on the exported artifact
    src/ledger/           ledger core library
    tests/                pytest suite (unit + repo hygiene)

## Running the pipeline locally

    python3 ci/runner.py --pipeline ci/pipeline.json --repo "$PWD" \\
        --work-root /tmp/team-ci/work --cache-dir /tmp/team-ci/cache \\
        --summary /tmp/team-ci/summary.json

Exit code 0 means every job passed; the summary JSON records each step's
status, the cache events, and the number of tests that passed. A second
run right after the first reuses the dependency cache from
`--cache-dir`, so the install step is skipped. Pipelines never write
into the checkout: generated output goes to the work/cache dirs.
"""

GITIGNORE = """__pycache__/
*.pyc
.pytest_cache/
dist/
.deps/
build/
out/
release/
artifacts/
.team-ci/
"""

LEDGER_INIT = '''"""ledger registry package."""
from .core import Ledger, LedgerError
from .core import UnknownAccount, InsufficientFunds, NegativeAmount

__all__ = ["Ledger", "LedgerError", "UnknownAccount", "InsufficientFunds",
           "NegativeAmount"]
__version__ = "1.4.0"
'''

LEDGER_CORE = '''"""Core primitives for the shared ledger registry.

A Ledger holds named accounts with integer balances in minor units.
Posting moves money from a debit account to a credit account, raising the
appropriate domain error on unknown accounts, negative amounts, or
insufficient funds. The total across all accounts is invariant under
posting (it equals the sum of the opening balances).
"""


class LedgerError(Exception):
    """Base class for ledger domain errors."""


class UnknownAccount(LedgerError):
    """A transaction referenced an account that was never opened."""


class InsufficientFunds(LedgerError):
    """A posting would overdraw the debit account."""


class NegativeAmount(LedgerError):
    """Amounts must be non-negative integers in minor units."""


def _check_amount(amount):
    if not isinstance(amount, int):
        raise NegativeAmount("amounts are integer minor units")
    if amount < 0:
        raise NegativeAmount("amount must be non-negative: %r" % amount)
    return amount


class Ledger:
    """A minimal double-entry ledger keyed by account name."""

    def __init__(self, opening=None):
        self._balances = {}
        self._order = []
        if opening:
            for name, balance in opening.items():
                self.open(name, balance)

    def open(self, name, opening=0):
        _check_amount(opening)
        if not name:
            raise LedgerError("account name cannot be empty")
        if name in self._balances:
            raise LedgerError("account already open: %s" % name)
        self._balances[name] = opening
        self._order.append(name)
        return self

    def balance(self, name):
        if name not in self._balances:
            raise UnknownAccount(name)
        return self._balances[name]

    def post(self, debit, credit, amount):
        """Move `amount` minor units from DEBIT to CREDIT."""
        _check_amount(amount)
        if debit not in self._balances:
            raise UnknownAccount(debit)
        if credit not in self._balances:
            raise UnknownAccount(credit)
        if amount > self._balances[debit]:
            raise InsufficientFunds(
                "%s holds %d, posting requires %d"
                % (debit, self._balances[debit], amount))
        self._balances[debit] -= amount
        self._balances[credit] += amount

    def total(self):
        return sum(self._balances.values())

    def account_names(self):
        return list(self._order)

    def to_dict(self):
        return {name: self._balances[name] for name in self._order}
'''

TEST_CORE = '''"""Unit tests for the ledger core primitives."""
import pytest

from src.ledger import (
    Ledger, LedgerError, UnknownAccount, InsufficientFunds, NegativeAmount,
)


def make_ledger():
    return Ledger().open("cash", 1000).open("income", 0).open("expense", 0)


def test_open_creates_account():
    ledger = Ledger().open("cash", 0)
    assert ledger.balance("cash") == 0


def test_open_records_opening_balance():
    ledger = Ledger().open("cash", 500)
    assert ledger.balance("cash") == 500


def test_open_with_negative_opening_raises():
    with pytest.raises(NegativeAmount):
        Ledger().open("cash", -1)


def test_open_duplicate_account_raises():
    ledger = Ledger().open("cash", 0)
    with pytest.raises(LedgerError):
        ledger.open("cash", 1)


def test_open_empty_name_raises():
    with pytest.raises(LedgerError):
        Ledger().open("", 1)


def test_post_moves_balance():
    ledger = make_ledger()
    ledger.post("cash", "expense", 250)
    assert ledger.balance("cash") == 750
    assert ledger.balance("expense") == 250


def test_post_insufficient_funds_raises():
    ledger = make_ledger()
    with pytest.raises(InsufficientFunds):
        ledger.post("cash", "expense", 1001)


def test_failed_post_leaves_balances_untouched():
    ledger = make_ledger()
    with pytest.raises(InsufficientFunds):
        ledger.post("cash", "expense", 1001)
    assert ledger.balance("cash") == 1000
    assert ledger.balance("expense") == 0


def test_post_unknown_debit_raises():
    ledger = make_ledger()
    with pytest.raises(UnknownAccount):
        ledger.post("mystery", "expense", 1)


def test_post_unknown_credit_raises():
    ledger = make_ledger()
    with pytest.raises(UnknownAccount):
        ledger.post("cash", "mystery", 1)


def test_post_negative_amount_raises():
    ledger = make_ledger()
    with pytest.raises(NegativeAmount):
        ledger.post("cash", "expense", -5)


def test_total_conserved_across_posts():
    ledger = Ledger().open("cash", 1000).open("savings", 0)
    for amount in (1, 2, 3, 250):
        ledger.post("cash", "savings", amount)
    assert ledger.total() == 1000
    assert ledger.balance("cash") == 744
    assert ledger.balance("savings") == 256


def test_account_names_follow_open_order():
    ledger = Ledger().open("a", 1).open("b", 2).open("c", 3)
    assert ledger.account_names() == ["a", "b", "c"]


def test_to_dict_round_trip():
    ledger = make_ledger()
    ledger.post("cash", "expense", 100)
    data = ledger.to_dict()
    assert data["cash"] == 900
    assert data == {"cash": 900, "income": 0, "expense": 100}


def test_opening_mapping_populates_accounts():
    ledger = Ledger({"cash": 5, "income": 0})
    assert ledger.balance("cash") == 5
    assert ledger.balance("income") == 0
'''

TEST_HYGIENE = '''"""Repo hygiene: the checkout must stay free of generated output.

The pipeline runs this test in its (fresh) test workspace; a job that
built earlier in the same workspace would leave its output behind and
fail this assertion. See scripts/build.py for what the build emits.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED = {"dist", ".deps", "build", "release", "out", "artifacts",
             ".vendor", ".pytest_cache"}


def test_no_generated_output_at_checkout_root():
    present = {p.name for p in ROOT.iterdir() if p.is_dir()}
    leaked = sorted(GENERATED & present)
    assert not leaked, (
        "generated build/dependency output left in the checkout: %s" % leaked
    )


def test_expected_top_level_layout():
    assert (ROOT / "src").is_dir()
    assert (ROOT / "ci").is_dir()
    assert (ROOT / "tests").is_dir()
    assert not (ROOT / "dist").exists()
    assert not (ROOT / ".deps").exists()
'''

BUILD_PY = '''#!/usr/bin/env python3
"""Assemble the ledger wheel and sidecar artifacts into dist/.

Runs in a job workspace that has the vendored dependency installed into
.deps (the pipeline's install step); the ledgerlib import below fails if
that step was skipped without a valid cache.
"""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".deps"))
import ledgerlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
SRC = ROOT / "src"
DIST = ROOT / "dist"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(SRC.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert ledgerlib.tag() == "vendored-1.0.0", "dependency mismatch"
    DIST.mkdir(exist_ok=True)
    wheel = DIST / "ledger.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(SRC.rglob("*.py")):
            zf.write(f, f.relative_to(SRC).as_posix())
        zf.writestr("ledger/VERSION", "1.4.0\\n")
    (DIST / "sources.sha256").write_text(sources_digest() + "\\n")
    (DIST / "metadata.json").write_text(json.dumps({
        "package": "ledger",
        "version": "1.4.0",
        "wheel": "ledger.whl",
        "ledgerlib": ledgerlib.tag(),
    }, indent=2))
    print("built dist/ledger.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
'''

CHECK_ARTIFACT_PY = '''#!/usr/bin/env python3
"""Consumer-side artifact gate.

The artifact exported by the build job (contents of dist/) is expected to
be materialised at the root of this job's workspace: metadata.json,
ledger.whl and sources.sha256. The wheel must contain the current ledger
sources and the digest must match a fresh digest of src/ in this checkout.
"""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def sources_digest():
    h = hashlib.sha256()
    for f in sorted((ROOT / "src").rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    for required in ("metadata.json", "ledger.whl", "sources.sha256"):
        if not (ROOT / required).is_file():
            raise SystemExit("missing artifact file: %s" % required)
    meta = json.loads((ROOT / "metadata.json").read_text())
    assert meta["package"] == "ledger", meta
    assert meta["version"] == "1.4.0", meta
    with zipfile.ZipFile(ROOT / "ledger.whl") as zf:
        names = set(zf.namelist())
    expected_members = {"ledger/__init__.py", "ledger/core.py",
                        "ledger/VERSION"}
    missing = sorted(expected_members - names)
    if missing:
        raise SystemExit("wheel missing members: %s" % missing)
    got = (ROOT / "sources.sha256").read_text().strip()
    want = sources_digest()
    if got != want:
        raise SystemExit("sources digest mismatch: %s != %s" % (got, want))
    print("artifact ok: wheel=%s digest=%s" % (names and "yes", want[:12]))


if __name__ == "__main__":
    main()
'''

INSTALL_SH = """#!/usr/bin/env bash
# Install the repo's vendored dependency into the workspace-local .deps
# directory. The pipeline runs this step only on a cache miss.
set -euo pipefail
mkdir -p .deps
rm -rf .deps/ledgerlib
cp -r ci/vendor/ledgerlib .deps/ledgerlib
printf 'ledgerlib==1.0.0\\n' > .deps/DEPENDENCIES
echo "vendored dependencies installed (ledgerlib 1.0.0)"
"""

DEPS_LOCK = "ledgerlib==1.0.0\n"

VENDOR_INIT = '''"""Vendored ledgerlib runtime dependency (org internal)."""
from .core import tag  # noqa: F401

__version__ = "1.0.0"
'''

VENDOR_CORE = '''"""ledgerlib: tiny helpers the registry build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-1.0.0"


def minor_units(amount):
    """Normalise a float amount into integer minor units, or None."""
    if isinstance(amount, int):
        return amount
    if isinstance(amount, float) and amount.is_integer():
        return int(amount)
    return None
'''

PIPELINE_JSON = '''{
  "ci_version": 1,
  "jobs": {
    "build": {
      "steps": [
        {"step": "restore_cache",
         "key": "deps-{{hash:ci/deps.lock}}",
         "path": ".deps",
         "if": "always"},
        {"step": "run", "name": "install", "cmd": "bash ci/install.sh",
         "if": "cache_miss"},
        {"step": "run", "name": "build",
         "cmd": "python3 scripts/build.py", "if": "always"},
        {"step": "upload_artifacts", "path": "dist/", "if": "always"}
      ]
    },
    "test": {
      "needs": ["build"],
      "steps": [
        {"step": "download_artifacts", "from": "build", "if": "always"},
        {"step": "run", "name": "verify_artifact",
         "cmd": "python3 scripts/check_artifact.py", "if": "always"},
        {"step": "run", "name": "unit",
         "cmd": "python3 -m pytest -p no:cacheprovider -q tests/",
         "if": "always",
         "env": {"PYTHONDONTWRITEBYTECODE": "1"}}
      ]
    }
  }
}
'''


# --------------------------------------------------------------------------
# Assemble + commit.
# --------------------------------------------------------------------------
def init_repo():
    subprocess.run(GIT + ["init", "-q", "-b", "main"], check=True)
    subprocess.run(GIT + ["config", "user.name", "build"], check=True)
    subprocess.run(GIT + ["config", "user.email", "build@localhost"],
                   check=True)


init_repo()
write("README.md", README)
write(".gitignore", GITIGNORE)
commit("scaffold: repository layout and docs")

write("src/ledger/__init__.py", LEDGER_INIT)
write("src/ledger/core.py", LEDGER_CORE)
commit("ledger: double-entry core primitives")

write("tests/test_core.py", TEST_CORE)
commit("tests: unit coverage for the ledger core")

write("ci/runner.py", BUGGY_RUNNER)
write("ci/pipeline.json", PIPELINE_JSON)
write("ci/deps.lock", DEPS_LOCK)
write("ci/install.sh", INSTALL_SH)
write("ci/vendor/ledgerlib/__init__.py", VENDOR_INIT)
write("ci/vendor/ledgerlib/core.py", VENDOR_CORE)
commit("ci: team local runner and pipeline definition")

write("scripts/build.py", BUILD_PY)
commit("build: wheel assembly with sources digest")

write("scripts/check_artifact.py", CHECK_ARTIFACT_PY)
write("tests/test_repo_hygiene.py", TEST_HYGIENE)
commit("ci: artifact gate for consumer jobs")

os.chmod(OUT / "ci" / "install.sh", 0o755)
os.chmod(OUT / "scripts" / "build.py", 0o755)
os.chmod(OUT / "scripts" / "check_artifact.py", 0o755)
os.chmod(OUT / "ci" / "runner.py", 0o755)
commit("release: finalise repository state")

print("generated %s (%d commits)" % (OUT, len(subprocess.run(
    GIT + ["rev-list", "--count", "HEAD"], capture_output=True,
    text=True).stdout.strip())))