#!/usr/bin/env python3
"""team-ci runner: a small local CI that executes ci/pipeline.json.

This runner is shared by several repositories in the org. It:

  * parses a pipeline JSON (jobs with `needs:` and steps),
  * checks out the named repository into a throwaway workspace per job,
  * runs each job's steps in that workspace with an isolated shell,
  * exchanges files between jobs through an artifact store under the cache
    dir (a manifest of exported relative paths, re-materialised at the
    consumer workspace root),
  * keeps a dependency cache keyed on the content of the lockfile named in
    the step's `key` template, e.g. `deps-{{hash:ci/deps.lock}}`, and only
    saves a cache snapshot after the job's steps have populated it,
  * writes a machine-readable summary JSON.

The pipeline is green when every job's steps succeed; cached dependency
directories let a warm second run skip the install step entirely.

Usage:
    python3 ci/runner.py --pipeline <pipeline.json> --repo <dir> \
        --work-root <dir> --cache-dir <dir> --summary <out.json>
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

# Names that are never copied between workspaces: generated output and VCS
# metadata are rebuilt or restored per run, they are not part of the checkout.
IGNORED = frozenset({
    ".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".coverage",
    "dist", ".deps", ".vendor", "build", "release", "out", "artifacts",
})


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
    src = Path(ws) / rel_path
    if not src.exists() or not any(src.rglob("*")):
        return False
    tgt = Path(cache_dir) / (key + ".tar.gz")
    with tarfile.open(str(tgt), "w:gz") as tf:
        tf.add(str(src), arcname=rel_path)
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


def run_job(name, job_def, repo_root, ws_root, art_root, cache_dir, env_base):
    # Each job gets its own throwaway checkout, so one job's build output can
    # never leak into another job's test run.
    ws = fresh_workspace(repo_root, ws_root, name)
    steps = []
    cache_hit = False
    cache_entries = []
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
                cache_hit = hit
                cache_entries.append({"key": key, "path": step["path"],
                                      "hit": hit})
                out = ("cache_hit " if hit else "cache_miss ") + "key=" + key
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
                    files = download_artifacts(art_root, j, ws)
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

    # A dependency cache is only snapshotted after its job succeeded and the
    # restore was a miss: the directory the key refers to exists by then, so a
    # later run can skip the install step confidently.
    for entry in cache_entries:
        if ok and not entry["hit"]:
            archive_cache(cache_dir, entry["key"], entry["path"], ws)

    return {"status": "success" if ok else "failure",
            "steps": steps, "cache": cache_entries}


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

    result, failed_job = "success", None
    job_results = {}
    total_tests = {"collected": None, "passed": None}
    for name in order:
        res = run_job(name, jobs[name], repo_root, ws_root, art_root,
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