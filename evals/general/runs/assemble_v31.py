#!/usr/bin/env python3
"""Assemble hub/v3.1: uniform 786-task set.
- 763 retained tasks: normalized records from hub/v3.0 (minus removed
  cinder-hearth/drift-canyon); calm-canyon terminus records replaced by v3.1
  re-runs (memory fix), pi/claude calm-canyon records stay from v3.0.
- 23 new tasks: fresh normalized traces from general-v31-* jobs.
"""
import json, shutil, sys
from pathlib import Path

sys.path.insert(0, "/home/ee/general-eval-runs")
from importlib.machinery import SourceFileLoader
import importlib.util
loader = SourceFileLoader("tohub", "/home/ee/general-eval-runs/to_hub.py")
spec = importlib.util.spec_from_loader("tohub", loader)
tohub = importlib.util.module_from_spec(spec)
sys.modules["tohub"] = tohub
loader.exec_module(tohub)

V30 = Path("/home/ee/general-eval-runs/hub/v3.0")
V31 = Path("/home/ee/general-eval-runs/hub/v3.1")
JOBS = Path("/home/ee/general-eval-runs/jobs")
FINAL_NEW = Path("/home/ee/general-eval-runs/final-v31")
REMOVED = {"cinder-hearth", "drift-canyon"}
NEW_TASKS = {p.name for p in Path("/home/ee/pi-setup/evals/general/tasks").iterdir()
             if p.name in set("""amber-engine amber-guest dusk-wicket ember-spire glacier-basin
             kelp-berth marble-ridge marrow-vault myrtle-hearth pearl-gasket pewter-meridian
             pipit-archive raven-core river-ferry sable-journal sable-wharf sedge-hearth
             umbral-inlet velvet-terrace frost-link fume-wheel meadow-mural rust-orchid""".split())}

if V31.exists():
    shutil.rmtree(V31)

# ---- 1. retained records from v3.0 staging (layout: agent/vendor/model/task)
copied = 0
for agent_dir in V30.iterdir():
    if not agent_dir.is_dir():
        continue
    agent = agent_dir.name
    for vendor_dir in agent_dir.iterdir():
        if not vendor_dir.is_dir():
            continue
        for model_dir in vendor_dir.iterdir():
            if not model_dir.is_dir():
                continue
            for task_dir in model_dir.iterdir():
                task = task_dir.name
                if not task_dir.is_dir() or task in REMOVED:
                    continue
                if agent == "terminus-2" and task == "calm-canyon":
                    continue  # replaced by v3.1 re-run
                shutil.copytree(task_dir, V31 / agent / vendor_dir.name / model_dir.name / task)
                copied += 1
print("retained records:", copied)

# ---- 2. fresh records for the 23 new tasks (+ calm-canyon terminus)
MODEL = {"glm": "openrouter/z-ai/glm-5.3-flash",
         "dsk": "openrouter/deepseek/deepseek-v4-flash-0731"}
AGENT = {"pi": "pi", "terminus": "terminus-2", "claude": "claude-code"}
stats = {}
for job in sorted(p for p in JOBS.glob("general-v31-*") if p.is_dir()):
    name = job.name
    parts = name.replace("general-v31-", "").rsplit("-", 1)
    agent_key, model_key = parts[0], parts[1]
    agent = AGENT[agent_key]
    model = MODEL[model_key]
    model_slug = model.removeprefix("openrouter/")
    vendor, model_name = model_slug.split("/", 1)
    rewards, skipped = {}, []
    for trial in sorted(job.iterdir()):
        if not trial.is_dir() or "__" not in trial.name:
            continue
        task = trial.name.rsplit("__", 1)[0]
        if not (task in NEW_TASKS or (agent == "terminus-2" and task == "calm-canyon")):
            continue
        out = V31 / agent / vendor / model_name / task
        (out / "verifier").mkdir(parents=True, exist_ok=True)
        traj = tohub.CONVERTERS[agent](trial / "agent", task, model)
        md = {"task": task, "agent": agent, "model": model,
              "source_trial": trial.name}
        rfile = trial / "verifier" / "reward.txt"
        reward = None
        if rfile.exists():
            try:
                reward = float(rfile.read_text().strip())
            except ValueError:
                pass
        md["reward"] = reward
        md["agent_timeout"] = "AgentTimeoutError" in (
            (trial / "exception.txt").read_text() if (trial / "exception.txt").exists() else "")
        if traj is None:
            skipped.append(task)
            (out / "trajectory.json").write_text(json.dumps(
                {**md, "note": "no trace available"}, indent=1))
        else:
            traj["reward"] = reward
            traj["exception"] = (trial / "exception.txt").exists()
            (out / "trajectory.json").write_text(json.dumps(traj, ensure_ascii=False))
        (out / "metadata.json").write_text(json.dumps(md, indent=1))
        for f in ("reward.txt", "test-stdout.txt"):
            if (trial / "verifier" / f).exists():
                shutil.copy(trial / "verifier" / f, out / "verifier" / f)
        rewards[task] = reward if reward is not None else 0.0
    total = sum(rewards.values())
    stats[name] = {"agent": agent, "model": model, "n_tasks": len(rewards),
                   "total_reward": round(total, 2),
                   "no_trace_tasks": skipped}
    print(f"{name}: {len(rewards)} tasks, reward {total:.2f}, no-trace {len(skipped)}")

# ---- 3. per-run results.json + summary
for run, st in stats.items():
    agent = st["agent"]
    vendor, model_name = st["model"].removeprefix("openrouter/").split("/", 1)
    (V31 / agent / vendor / model_name / "results.json").write_text(json.dumps(
        {"run": run, **st, "pass_rate_786": round(st["total_reward"] / 786, 4)}, indent=1))

# retained-run results (from v3.0, denominator updated, removed tasks dropped,
# calm-canyon terminus replaced)
def retained_results(agent: str, model_slug: str, model: str, run: str):
    d = V31 / agent / model_slug  # model_slug = vendor/model
    total, n = 0.0, 0
    for t in d.iterdir():
        if not t.is_dir():
            continue
        md = json.loads((t / "metadata.json").read_text())
        r = md.get("reward")
        total += float(r) if r is not None else 0.0
        n += 1
    (d / "results.json").write_text(json.dumps(
        {"run": run, "agent": agent, "model": model, "n_tasks": n,
         "total_reward": round(total, 2), "pass_rate_786": round(total / 786, 4),
         "note": "v3.0 records retained (task unchanged in v3.1)" +
                 ("; calm-canyon re-run at memory_mb=4096" if agent == "terminus-2" else "")},
        indent=1))
    return total, n

for agent, slug, model, run in [
    ("pi", "z-ai/glm-5.3-flash", MODEL["glm"], "general-pi-glm (v3.0 retained + v3.1 new)"),
    ("pi", "deepseek/deepseek-v4-flash-0731", MODEL["dsk"], "general-pi-dsk (v3.0 retained + v3.1 new)"),
    ("terminus-2", "z-ai/glm-5.3-flash", MODEL["glm"], "general-terminus-glm (v3.0 retained* + v3.1 new)"),
    ("terminus-2", "deepseek/deepseek-v4-flash-0731", MODEL["dsk"], "general-terminus-dsk (v3.0 retained* + v3.1 new)"),
    ("claude-code", "z-ai/glm-5.3-flash", "z-ai/glm-5.3-flash", "general-claude-glm (v3.0 retained + v3.1 new)"),
    ("claude-code", "deepseek/deepseek-v4-flash-0731", "deepseek/deepseek-v4-flash-0731", "general-claude-dsk (v3.0 retained + v3.1 new)")]:
    total, n = retained_results(agent, slug, model, run)
    print(f"{agent} {slug}: {n} tasks, reward {total:.2f}")

(V31 / "summary.json").write_text(json.dumps({
    "dataset": "pi-setup/evals/general @ pi-setup 20dc8962 (786 tasks)",
    "changes_from_v3.0": {
        "removed": sorted(REMOVED) + ["(cinder-hearth: image build bug; drift-canyon: verifier bug)"],
        "added": sorted(NEW_TASKS),
        "modified": {"calm-canyon": "memory_mb 2048->4096; terminus-2 re-run, pi/claude-code v3.0 records retained"},
        "renamed": "23 new tasks carry opaque two-word IDs (deepswe/tblite markers scrubbed)"},
    "note": "Records for the 763 retained tasks are identical to v3.0 (duplicated here for a uniform set). "
            "Traces: reasoning_content on reasoning turns, tool_calls paired with tool results, per-record tool definitions. "
            "Episodes cut by agent timeout end on a tool_call without a result (faithful to the raw session).",
    "runs": stats}, indent=1))
print("staged:", V31)
