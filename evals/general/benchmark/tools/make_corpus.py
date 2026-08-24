#!/usr/bin/env python3
"""Select a small reference corpus from the source datasets.

Copies sampled tasks into benchmark/reference/corpus/ so workflow subagents
can consult them without the 10GB of raw data getting in the way.
"""
import json, random, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "reference"
OUT = REF / "corpus"

random.seed(42)

def pick_nemotron(base: Path, category: str, n: int, prefix: str):
    cat = base / category
    if not cat.is_dir():
        return []
    dirs = sorted(p for p in cat.iterdir() if p.is_dir())
    random.shuffle(dirs)
    picked = []
    for d in dirs[:n]:
        dest = OUT / f"{prefix}-{d.name}"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(d, dest)
        picked.append(str(dest.relative_to(ROOT)))
    return picked

def pick_tmax(base: Path, n: int, prefix: str):
    dirs = sorted(p for p in base.iterdir() if p.is_dir() and (p / "task.json").exists())
    random.shuffle(dirs)
    picked = []
    for d in dirs[:n]:
        dest = OUT / f"{prefix}-{d.name}"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(d, dest)
        picked.append(str(dest.relative_to(ROOT)))
    return picked

def main():
    OUT.mkdir(exist_ok=True)
    manifest = {"nemotron_easy": {}, "nemotron_medium": {}, "tmax": []}
    easy = REF / "nemotron_easy/easy_5000"
    med = REF / "nemotron_medium/medium_20000"

    for cat in ["data_processing", "data_querying", "data_science", "debugging",
                "dependency_management", "file_operations", "scientific_computing",
                "security", "software_engineering"]:
        manifest["nemotron_easy"][cat] = pick_nemotron(easy, cat, 3, "nem-easy")

    for cat in ["data_science", "debugging", "file_operations", "model_training",
                "scientific_computing", "security", "software_engineering",
                "system_administration"]:
        manifest["nemotron_medium"][cat] = pick_nemotron(med, cat, 3, "nem-med")

    manifest["tmax"] = pick_tmax(REF / "tmax", 25, "tmax")

    (OUT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))
    total = sum(len(v) if isinstance(v, list) else sum(len(x) for x in v.values())
                for v in manifest.values())
    print(f"corpus written: {total} tasks in {OUT}")

if __name__ == "__main__":
    main()
