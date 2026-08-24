#!/usr/bin/env python3
"""Static lint for all benchmark tasks. Usage: python3 tools/lint_tasks.py [--verbose]"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "tasks"
PLAN = json.loads((ROOT / "specs/plan.json").read_text())
EXPECTED = {t["name"]: t for t in PLAN["item_tasks"] + PLAN["skill_tasks"]}

ALLOWED_BASES = ("bench-base:",)
CA_MARKERS = ("update-ca-certificates", "corp-root-ca")

def lint_task(d: Path) -> list[str]:
    errs = []
    name = d.name
    if name not in EXPECTED and name != "golden-example":
        errs.append("not in plan.json")
    for f in ["task.toml", "instruction.md", "environment/Dockerfile",
              "solution/solve.sh", "tests/test.sh"]:
        p = d / f
        if not p.exists():
            errs.append(f"missing {f}")
        elif p.stat().st_size == 0 and f != "instruction.md":
            errs.append(f"empty {f}")
    if errs:
        return errs

    df = (d / "environment/Dockerfile").read_text()
    from_lines = [l for l in df.splitlines() if l.strip().upper().startswith("FROM ")]
    if not from_lines:
        errs.append("Dockerfile has no FROM")
    else:
        img = from_lines[0].split()[1]
        if not img.startswith(ALLOWED_BASES):
            if not all(m in df for m in CA_MARKERS):
                errs.append(f"non-bench-base FROM '{img}' without CA patch")
            if not (d / "environment/corp-root-ca.pem").exists():
                errs.append(f"non-bench-base FROM '{img}' missing environment/corp-root-ca.pem")
    if "WORKDIR" not in df:
        errs.append("Dockerfile has no WORKDIR")

    tt = (d / "task.toml").read_text()
    for key in ["schema_version", "[verifier]", "[agent]", "[environment]"]:
        if key not in tt:
            errs.append(f"task.toml missing {key}")
    try:
        try:
            import tomllib
        except ModuleNotFoundError:
            import pip._vendor.tomli as tomllib
        tomllib.loads(tt)
    except Exception as e:
        errs.append(f"task.toml TOML parse error: {e}")

    inst = (d / "instruction.md").read_text()
    if len(inst.strip()) < 50:
        errs.append("instruction.md too short")

    ts = (d / "tests/test.sh").read_text()
    if "/logs/verifier/reward" not in ts:
        errs.append("test.sh never writes reward")
    sol = (d / "solution/solve.sh").read_text()
    if len(sol.strip()) < 20:
        errs.append("solve.sh suspiciously short")

    # plan conformance
    if name in EXPECTED:
        exp = EXPECTED[name]
        meta_diff = re.search(r'difficulty\s*=\s*"(\w+)"', tt)
        if meta_diff and meta_diff.group(1) != exp["difficulty"]:
            errs.append(f"difficulty {meta_diff.group(1)} != plan {exp['difficulty']}")
    return errs

def main():
    verbose = "--verbose" in sys.argv
    report = {}
    for d in sorted(TASKS.iterdir()):
        if not d.is_dir():
            continue
        errs = lint_task(d)
        report[d.name] = errs
        if errs and verbose:
            print(f"FAIL {d.name}: " + "; ".join(errs))
    n_ok = sum(1 for v in report.values() if not v)
    n_bad = sum(1 for v in report.values() if v)
    missing = sorted(set(EXPECTED) - set(report))
    print(f"\n== lint: {n_ok} ok, {n_bad} bad, {len(missing)} not yet created (of {len(EXPECTED)} planned)")
    if n_bad and not verbose:
        print("bad tasks:", ", ".join(k for k, v in report.items() if v)[:2000])
    (ROOT / "specs/lint_report.json").write_text(json.dumps(
        {"ok": n_ok, "bad": {k: v for k, v in report.items() if v}, "missing": missing}, indent=1))

if __name__ == "__main__":
    main()
