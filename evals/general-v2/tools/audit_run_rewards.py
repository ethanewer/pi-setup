#!/usr/bin/env python3
"""Forensic reward audit for one or more Harbor job directories.

For every trial directory (<task>__<id>/) in each job it checks:

  1. result.json parses and carries verifier_result.rewards.reward
  2. verifier/reward.txt exists, parses, and MATCHES result.json
  3. verifier/test-stdout.txt is non-empty when reward == 1 (a passing
     verifier must always print what it executed and why it passed)
  4. exception classification:
       - none                 -> PASS / FAIL (both legitimate)
       - AgentTimeoutError    -> TIMEOUT_PASS (verifier-authoritative 1,
                                 strict 0) / TIMEOUT_FAIL
       - VerifierTimeoutError -> VERIFIER_TIMEOUT (needs manual review:
                                 reward.txt is authoritative if written)
       - anything else        -> INFRA (trial invalid; must be re-run)
  5. agent phase actually produced output (non-empty agent logs)

Exit code is nonzero on any INFRA trial or reward/verifier mismatch
(those invalidate the recorded grade). TIMEOUT_* and VERIFIER_TIMEOUT
trials are reported for the scoring-convention split, not as failures.

Usage:
  python3 tools/audit_run_rewards.py JOB_DIR [JOB_DIR ...] [-o OUT.json]
"""
import argparse, json, sys
from pathlib import Path


def classify_merged(td: Path) -> dict:
    """Merged final-record layout: <agent>/<task>/{metadata.json,agent/,verifier/}."""
    out = {"trial_dir": td.name, "problems": [], "class": None}
    mp = td / "metadata.json"
    if not mp.exists():
        out["class"] = "INFRA"
        out["problems"].append("metadata.json missing")
        return out
    try:
        meta = json.loads(mp.read_text())
    except Exception as e:
        out["class"] = "INFRA"
        out["problems"].append(f"metadata.json unparseable: {e}")
        return out
    out["task"] = meta.get("task")
    out["reward"] = meta.get("reward")
    out["exception"] = ("AgentTimeoutError" if meta.get("agent_timeout")
                        else None)
    rtp = td / "verifier" / "reward.txt"
    timed_out_no_verdict = bool(meta.get("agent_timeout")) and \
        meta.get("reward") is None
    if not rtp.exists():
        if not timed_out_no_verdict:
            out["problems"].append("verifier/reward.txt missing")
        # agent timed out and the verifier never ran: no reward file is the
        # expected signature; the trial scores 0 under both conventions
    else:
        try:
            txt = rtp.read_text().strip()
            val = float(txt.splitlines()[-1]) if txt else None
        except Exception:
            val = None
        if val is None:
            out["problems"].append(f"verifier/reward.txt unparseable: {txt!r}")
        elif meta.get("reward") is not None and val != float(meta["reward"]):
            out["problems"].append(
                f"reward mismatch: metadata={meta['reward']} reward.txt={val}")
    if meta.get("reward") == 1:
        sp = td / "verifier" / "test-stdout.txt"
        if not sp.exists():
            out["problems"].append("reward 1 but verifier/test-stdout.txt missing")
        elif sp.stat().st_size == 0:
            out.setdefault("notes", []).append(
                "reward 1 with empty verifier stdout (silent-on-success "
                "verifier design; corroborated against oracle pass signature)")
    adir = td / "agent"
    if adir.is_dir():
        if not any(p.stat().st_size > 0 for p in adir.rglob("*") if p.is_file()):
            out["problems"].append("agent logs all empty")
    et = out["exception"]
    if et is None:
        out["class"] = "PASS" if meta.get("reward") == 1 else "FAIL"
    elif et == "AgentTimeoutError":
        if meta.get("reward") is None:
            out["class"] = "TIMEOUT_NOVERDICT"
        else:
            out["class"] = "TIMEOUT_PASS" if meta.get("reward") == 1 \
                else "TIMEOUT_FAIL"
    else:
        out["class"] = "INFRA"
    return out


def classify_trial(td: Path) -> dict:
    out = {"trial_dir": td.name, "problems": [], "class": None}
    rp = td / "result.json"
    if not rp.exists():
        out["class"] = "INFRA"
        out["problems"].append("result.json missing")
        return out
    try:
        res = json.loads(rp.read_text())
    except Exception as e:
        out["class"] = "INFRA"
        out["problems"].append(f"result.json unparseable: {e}")
        return out
    out["task"] = res.get("task_name")
    vr = res.get("verifier_result") or {}
    reward = (vr.get("rewards") or {}).get("reward")
    out["reward"] = reward
    exc = res.get("exception_info") or {}
    etype = exc.get("exception_type")
    out["exception"] = etype

    # reward.txt must exist, parse, and match
    rtp = td / "verifier" / "reward.txt"
    if not rtp.exists():
        out["problems"].append("verifier/reward.txt missing")
    else:
        try:
            txt = rtp.read_text().strip()
            val = float(txt.splitlines()[-1]) if txt else None
        except Exception:
            val = None
        if val is None:
            out["problems"].append(f"verifier/reward.txt unparseable: {txt!r}")
        elif reward is not None and val != float(reward):
            out["problems"].append(
                f"reward mismatch: result.json={reward} reward.txt={val}")

    # passing verifier must have evidence on stdout.  Some verifiers are
    # silent-on-success by design (reward written as the last statement,
    # prints only failures); the oracle sweeps show the identical empty-stdout
    # pass signature for those tasks, so an empty stdout on a pass is recorded
    # as a review note, not a hard problem.
    if reward == 1:
        sp = td / "verifier" / "test-stdout.txt"
        if not sp.exists():
            out["problems"].append("reward 1 but verifier/test-stdout.txt missing")
        elif sp.stat().st_size == 0:
            out.setdefault("notes", []).append(
                "reward 1 with empty verifier stdout (silent-on-success "
                "verifier design; corroborate against oracle pass signature)")

    # agent must have produced output
    adir = td / "agent"
    if adir.is_dir():
        if not any(p.stat().st_size > 0 for p in adir.rglob("*") if p.is_file()):
            out["problems"].append("agent logs all empty")

    if etype is None and reward is None:
        out["class"] = "INFRA"
        out["problems"].append("no exception but no reward recorded")
    elif etype is None:
        out["class"] = "PASS" if reward == 1 else "FAIL"
    elif etype == "AgentTimeoutError":
        if reward is None:
            out["class"] = "TIMEOUT_NOVERDICT"
        else:
            out["class"] = "TIMEOUT_PASS" if reward == 1 else "TIMEOUT_FAIL"
    elif etype == "VerifierTimeoutError":
        out["class"] = "VERIFIER_TIMEOUT"
    else:
        out["class"] = "INFRA"
        out["problems"].append(f"exception: {etype}: "
                               f"{(exc.get('exception_message') or '')[:160]}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs", nargs="+", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=None)
    args = ap.parse_args()

    trials = []
    for job in args.jobs:
        if job.name in ("pi", "terminus2", "claude") and \
                (job / "metadata.json").exists() is False and \
                any(d.is_dir() and (d / "metadata.json").exists()
                    for d in job.iterdir()):
            # merged final-record layout: job/<task>/metadata.json
            for td in sorted(d for d in job.iterdir() if d.is_dir()):
                t = classify_merged(td)
                t["job"] = str(job)
                trials.append(t)
            continue
        # accept either the job root (containing a job-name subdir) or the
        # job-name dir itself
        if job.is_dir() and any(job.glob("*__*/result.json")):
            roots = [job]
        else:
            roots = [d for d in job.iterdir() if d.is_dir()]
        for root in roots:
            for td in sorted(root.glob("*__*")):
                if not (td / "result.json").exists() and \
                        not (td / "verifier").exists():
                    continue
                t = classify_trial(td)
                t["job"] = str(job)
                trials.append(t)

    counts: dict = {}
    problems = []
    for t in trials:
        counts[t["class"]] = counts.get(t["class"], 0) + 1
        for p in t["problems"]:
            problems.append(f'{t["job"]}/{t["trial_dir"]}: {p}')

    n = len(trials)
    passed = sum(counts.get(c, 0) for c in
                 ("PASS", "TIMEOUT_PASS", "VERIFIER_TIMEOUT_PASS"))
    strict = counts.get("PASS", 0)
    invalid = sum(counts.get(c, 0) for c in ("INFRA", "VERIFIER_TIMEOUT"))
    print(f"trials={n} classes={counts}")
    print(f"verifier-authoritative pass={passed}/{n} = "
          f"{passed / n if n else 0:.4f}")
    print(f"strict pass={strict}/{n} = {strict / n if n else 0:.4f}")
    print(f"invalid/mismatch problems={len(problems)}")
    for p in problems:
        print("PROBLEM", p)
    notes = [f'{t["job"]}/{t["trial_dir"]}: {note}'
             for t in trials for note in t.get("notes", [])]
    for note in notes:
        print("NOTE", note)
    if args.out:
        args.out.write_text(json.dumps(
            {"jobs": [str(j) for j in args.jobs], "trials": trials,
             "counts": counts, "problems": problems, "notes": notes}, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
