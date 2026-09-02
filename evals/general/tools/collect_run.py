#!/usr/bin/env python3
"""Merge Harbor job trial directories into the final per-task record layout.

Output layout (same as the HF dataset v2/<agent>/<task>/ records):

  OUT/<agent>/<task>/agent/          agent logs (copied verbatim)
  OUT/<agent>/<task>/verifier/       reward.txt, test-stdout.txt
  OUT/<agent>/<task>/metadata.json   task, agent, reward, agent_timeout,
                                     source_trial, model
  OUT/<agent>/<task>/exception.txt   only if the trial recorded an exception

Selection: job directories are given in priority order (later = higher);
per task, the highest-priority job with a VALID trial for that task wins
(a trial is valid when result.json exists and its exception, if any, is a
recognized agent-side outcome — i.e. not a missing-result infra failure).
Within a job with several attempts for one task, the latest finished trial
wins.  Tasks present in no job are reported as missing.

Usage:
  python3 tools/collect_run.py --agent pi --model openrouter/... \
      --out OUT ROOT1 [ROOT2 ...]

Each ROOT is either a job dir containing <task>__<id>/ trial dirs directly,
or a parent containing one job subdir (e.g. /mnt/jobs/bench-pi-glm/pi-glm).
"""
import argparse, json, shutil, sys
from pathlib import Path

AGENT_LOG_FILES = ("pi.txt", "trajectory.json", "terminus_2.pane",
                   "recording.cast", "claude.txt", "claude-code.txt")


def find_trial_roots(root: Path):
    if any(root.glob("*__*/result.json")) or any(root.glob("*__*/verifier")):
        return [root]
    return [d for d in root.iterdir() if d.is_dir()]


def collect_trials(job: Path):
    """Return {task: trial_dir} picking the latest finished trial per task."""
    best = {}
    for root in find_trial_roots(job):
        for td in sorted(root.glob("*__*")):
            rp = td / "result.json"
            if not rp.exists():
                continue
            try:
                res = json.loads(rp.read_text())
            except Exception:
                continue
            task = res.get("task_name") or td.name.split("__")[0]
            fin = res.get("finished_at") or ""
            if task not in best or fin > best[task][1]:
                best[task] = (td, fin, res)
    return {t: v[0] for t, v in best.items()}


def is_valid_trial(td: Path) -> bool:
    rp = td / "result.json"
    if not rp.exists():
        return False
    try:
        res = json.loads(rp.read_text())
    except Exception:
        return False
    exc = (res.get("exception_info") or {}).get("exception_type")
    if exc and exc not in ("AgentTimeoutError", "VerifierTimeoutError",
                           "UnknownApiError", "NetworkConnectionError",
                           "NonZeroAgentExitCodeError"):
        # unrecognized exception with no verdict -> treat as invalid
        reward = ((res.get("verifier_result") or {}).get("rewards") or {}) \
            .get("reward")
        return reward is not None
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("jobs", nargs="+", type=Path)
    args = ap.parse_args()

    merged = {}
    missing = []
    for job in args.jobs:
        if not job.exists():
            print(f"WARN job dir missing: {job}")
            continue
        trials = collect_trials(job)
        for task, td in trials.items():
            merged.setdefault(task, []).append((job, td))

    out_root = args.out / args.agent
    out_root.mkdir(parents=True, exist_ok=True)

    for task, candidates in sorted(merged.items()):
        chosen = None
        for job, td in reversed(candidates):  # later jobs win
            if is_valid_trial(td):
                chosen = (job, td)
                break
        if chosen is None:
            missing.append(task)
            continue
        job, td = chosen
        try:
            res = json.loads((td / "result.json").read_text())
        except Exception:
            missing.append(task)
            continue
        rec = out_root / task
        if rec.exists():
            shutil.rmtree(rec)
        rec.mkdir()
        # agent logs
        aout = rec / "agent"
        adir = td / "agent"
        if adir.is_dir():
            shutil.copytree(adir, aout)
        # verifier artifacts
        vout = rec / "verifier"
        vdir = td / "verifier"
        vout.mkdir()
        for name in ("reward.txt", "test-stdout.txt"):
            if (vdir / name).exists():
                shutil.copy2(vdir / name, vout / name)
        # metadata
        vr = res.get("verifier_result") or {}
        reward = (vr.get("rewards") or {}).get("reward")
        exc = res.get("exception_info") or {}
        meta = {
            "task": task,
            "agent": args.agent,
            "reward": reward,
            "agent_timeout": exc.get("exception_type") == "AgentTimeoutError",
            "source_trial": td.name,
            "model": args.model,
        }
        (rec / "metadata.json").write_text(json.dumps(meta, indent=2) + "\n")
        if exc.get("exception_type"):
            (rec / "exception.txt").write_text(
                f"{exc.get('exception_type')}: "
                f"{(exc.get('exception_message') or '')}\n")

    have = {p.name for p in out_root.iterdir() if p.is_dir()}
    want = set(merged)
    print(f"agent={args.agent} records={len(have)} "
          f"tasks_seen={len(want)} unresolved={sorted(want - have)}")
    if missing:
        print("MISSING (invalid or errored in every job):", sorted(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
