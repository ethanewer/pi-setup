#!/usr/bin/env python3
"""Generate the canonical task plan from skills.json.

Outputs specs/plan.json:
  - item_tasks: per item, a main (easy/medium) task and, when the combined
    skill depth >= 8, a hard task.
  - skill_tasks: per technical skill, an easy/trivial probe task.
  - skill_map: normalized skill -> items + the task names that must cover it.

The canonical_task_plan.json (human/LLM authored later) fills in titles,
descriptions, base images, and corpus pointers keyed by task name.
"""
import json, re, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS = json.loads((ROOT.parent / "skills.json").read_text())

def slug(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

def norm_skill(s: str) -> str:
    return " ".join(s.strip().lower().split())

def main():
    item_tasks = []
    for it in SKILLS:
        iid = it["id"]
        soft = it["agentic_soft_skills"]
        tech = it["technical_skills"]
        depth = len(soft) + len(tech)
        main_task = {
            "name": f"{iid}-main",
            "item": iid,
            "difficulty": "medium" if depth >= 5 else "easy",
            "kind": "main",
            "soft_skills": soft,
            "technical_skills": tech,
        }
        item_tasks.append(main_task)
        if depth >= 8:
            item_tasks.append({
                "name": f"{iid}-hard",
                "item": iid,
                "difficulty": "hard",
                "kind": "hard",
                "soft_skills": soft,
                "technical_skills": tech,
            })

    skill_to_items = defaultdict(list)
    for it in SKILLS:
        for t in it["technical_skills"]:
            n = norm_skill(t)
            if it["id"] not in skill_to_items[n]:
                skill_to_items[n].append(it["id"])

    skill_tasks = []
    for n in sorted(skill_to_items):
        skill_tasks.append({
            "name": f"skill-{slug(n)}",
            "skill": n,
            "difficulty": "easy",
            "kind": "skill-probe",
            "items": skill_to_items[n],
        })

    plan = {
        "counts": {
            "items": len(SKILLS),
            "item_tasks": len(item_tasks),
            "hard_tasks": sum(1 for t in item_tasks if t["kind"] == "hard"),
            "skill_tasks": len(skill_tasks),
            "unique_technical_skills": len(skill_to_items),
        },
        "item_tasks": item_tasks,
        "skill_tasks": skill_tasks,
    }
    out = ROOT / "specs/plan.json"
    out.write_text(json.dumps(plan, indent=2))
    print(json.dumps(plan["counts"], indent=2))

if __name__ == "__main__":
    main()
