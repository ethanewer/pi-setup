#!/usr/bin/env python3
"""Live git-deployment verifier for fern-hearth.

Drives pushes into /app/repo.git through the candidate post-receive hook and
checks that /app/deployed faithfully mirrors pushed branch trees, handles branch
deletion and in-place updates, safely ignores non-branch refs, and never writes
outside /app/deployed.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = "/app/repo.git"
DEPLOY = "/app/deployed"

ENV = dict(os.environ,
           GIT_AUTHOR_NAME="verify",
           GIT_AUTHOR_EMAIL="verify@harness.local",
           GIT_COMMITTER_NAME="verify",
           GIT_COMMITTER_EMAIL="verify@harness.local")


def git(*args, cwd=None, data=None):
    r = subprocess.run(["git"] + list(args), cwd=cwd, env=ENV,
                       input=data, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("git %s rc=%s: %s"
                           % (tuple(args), r.returncode,
                              r.stderr.decode(errors="replace").strip()))
    return r


def branch_sha(branch):
    return git("--git-dir", REPO, "rev-parse", "refs/heads/" + branch) \
        .stdout.decode().strip()


def archive_to_map(sha):
    blob = git("--git-dir", REPO, "archive", sha).stdout
    tmp = tempfile.mkdtemp(prefix="fharc_")
    try:
        subprocess.run(["tar", "-xf", "-", "-C", tmp], input=blob,
                       capture_output=True, check=True)
        mapping = {}
        for root, _d, files in os.walk(tmp):
            for fn in files:
                key = os.path.relpath(os.path.join(root, fn), tmp)
                with open(os.path.join(root, fn), "rb") as f:
                    mapping[key] = f.read()
        return mapping
    finally:
        shutil.rmtree(tmp)


def deploy_map(branch):
    d = os.path.join(DEPLOY, branch)
    if not os.path.isdir(d):
        return None
    mapping = {}
    for root, _d, files in os.walk(d):
        for fn in files:
            key = os.path.relpath(os.path.join(root, fn), d)
            with open(os.path.join(root, fn), "rb") as f:
                mapping[key] = f.read()
    return mapping


def check_mirror(branch, sha):
    exp = archive_to_map(sha)
    act = deploy_map(branch)
    if act is None:
        return "deployed dir missing: " + branch
    if set(exp) != set(act):
        return ("tree mismatch for %r: only-expected=%r only-actual=%r"
                % (branch, sorted(set(exp) - set(act)), sorted(set(act) - set(exp))))
    for key, val in exp.items():
        if act.get(key) != val:
            return "byte mismatch on %r (%d vs %d bytes)" % (key, len(val), len(act.get(key)))
    return None


def make_clone():
    wd = tempfile.mkdtemp(prefix="fhcl_")
    git("clone", "-q", REPO, os.path.join(wd, "c"))
    return os.path.join(wd, "c")


def branch_exists(branch):
    try:
        git("--git-dir", REPO, "rev-parse", "--verify", "--quiet",
            "refs/heads/" + branch)
        return True
    except RuntimeError:
        return False


def commit_clone(c, files):
    for path, content in files.items():
        p = os.path.join(c, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(content.encode())
    git("-C", c, "add", "-A")
    git("-C", c, "commit", "-q", "-m", "scenario commit")


def push_branch(branch, files):
    c = make_clone()
    if branch_exists(branch):
        # in-place update: base the new commit on the current tip (fast-forward)
        git("-C", c, "fetch", "-q", "origin")
        git("-C", c, "checkout", "-B", branch, "origin/" + branch)
    commit_clone(c, files)
    r = subprocess.run(["git", "-C", c, "push", "-q", "origin",
                        "HEAD:refs/heads/" + branch],
                       env=ENV, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("push of %r failed: %s"
                           % (branch, r.stderr.decode()))
    return branch_sha(branch)


def push_delete(branch):
    c = make_clone()
    r = subprocess.run(["git", "-C", c, "push", "origin", ":refs/heads/" + branch],
                       env=ENV, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("delete push of %r failed: %s"
                           % (branch, r.stderr.decode()))


def push_tag(tagref):
    c = make_clone()
    tag = tagref.rsplit("/", 1)[-1]
    git("-C", c, "tag", tag, "main")
    r = subprocess.run(["git", "-C", c, "push", "-q", "origin", tagref],
                       env=ENV, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("tag push of %r failed: %s"
                           % (tagref, r.stderr.decode()))


def main():
    with open("/tests/hidden/cases_git.json", encoding="utf-8") as f:
        spec = json.load(f)
    cases = spec["cases"]

    failures = []

    # Snapshot /app top-level; the hook must never write outside /app/deployed.
    app_before = sorted(os.listdir("/app"))

    # 1) main must already be deployed and be an exact mirror.
    try:
        err = check_mirror("main", branch_sha("main"))
        if err:
            failures.append("main-mirror: " + err)
    except RuntimeError as e:
        failures.append("main-mirror errored: %s" % e)

    for case in cases:
        kind = case["kind"]
        name = case.get("name", kind)
        try:
            if kind == "main-mirror":
                # verified separately above (existing main deployment must survive)
                pass
            elif kind == "push-branch":
                sha = push_branch(case["branch"], case["files"])
                err = check_mirror(case["branch"], sha)
                if err:
                    failures.append("%s: " % name + err)
            elif kind == "delete-branch":
                sha = push_branch(case["branch"], case["files"])
                err = check_mirror(case["branch"], sha)
                if err:
                    failures.append("%s (setup): " % name + err)
                push_delete(case["branch"])
                if os.path.isdir(os.path.join(DEPLOY, case["branch"])):
                    failures.append("%s: dir still present after branch deletion"
                                    % name)
            elif kind == "push-tag":
                push_tag(case["ref"])
                tag = case["ref"].rsplit("/", 1)[-1]
                if os.path.isdir(os.path.join(DEPLOY, tag)):
                    failures.append("%s: tag created a deployment dir" % name)
                stray = [os.path.join(DEPLOY, d) for d in os.listdir(DEPLOY)
                         if d == tag]
                if stray:
                    failures.append("%s: unexpected deploy entry %r" % (name, stray))
            else:
                failures.append("unknown case kind %r" % kind)
        except RuntimeError as e:
            failures.append("%s errored: %s" % (name, e))

    # Ensure the hook wrote nothing outside /app/deployed.
    app_stray = [x for x in os.listdir("/app") if os.path.isdir(os.path.join("/app", x)) and
                 x not in app_before and x != "deployed"]
    if app_stray:
        failures.append("hook created things outside /app/deployed: %r" % app_stray)

    # /app/deployed must not have gained extra stray branch dirs from tag pushes.
    expected_toplevel = {"main", "docs", "rel.2.0"}
    deployed_now = sorted(os.listdir(DEPLOY))
    if "docs" not in deployed_now or "rel.2.0" not in deployed_now:
        failures.append("expected deploy roots missing: %r" % deployed_now)
    unexpected = [d for d in deployed_now if d not in expected_toplevel]
    if unexpected:
        failures.append("unexpected deploy entries: %r" % unexpected)

    if failures:
        for f_ in failures:
            print("FAIL: %s" % f_)
        sys.exit(1)
    print("REPO-GIT-OK")
    sys.exit(0)


if __name__ == "__main__":
    main()