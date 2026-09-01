#!/usr/bin/env python3
"""Generates drift-quarry fixtures: the visible Cirque store, hidden stores,
and the expected reports. Run inside a container with pandas + pyarrow."""
import hashlib
import json
import os
import random
import shutil

import pandas as pd

TASK = "/task"
SITES_A = ["birth", "coire", "fissure", "gunbarrel", "hanging", "lipline",
           "moraine", "notch", "outwash", "prow", "rimed", "scarp"]
DANGER = ["low", "moderate", "considerable", "high"]


def dna_rows(rng, n, sites, colspec):
    rows = []
    for i in range(n):
        row = {}
        for name, kind in colspec:
            if kind == "site":
                row[name] = rng.choice(sites)
            elif kind == "date":
                d = 1 + (i % 28)
                row[name] = "20%02d-%02d-%02dT%02d:00:00Z" % (
                    20 + (i % 5), 1 + (i % 12), d, i % 24)
            elif kind == "int":
                row[name] = rng.randrange(0, 200)
            elif kind == "cat":
                row[name] = rng.choice(DANGER)
        rows.append(row)
    return rows


def write_parquet(rows, columns, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df = pd.DataFrame(rows, columns=columns)
    df.to_parquet(path, index=False, engine="pyarrow")
    return df


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def build(root, bucket, dataset, version, columns, colspec, parts,
          seed, tamper_key=None, schema_break_key=None):
    """Build a store under root/bucket; returns (manifest, per-part rows)."""
    store = os.path.join(root, bucket)
    if os.path.isdir(store):
        shutil.rmtree(store)
    manifest = {"dataset": dataset, "version": version, "columns": columns,
                "splits": []}
    rows_per_file = {}
    counter = 0
    for role, count in parts:
        entries = []
        for i in range(count):
            key = "%s/part-%03d.parquet" % (role, i)
            counter += 1
            rng = random.Random(seed * 1000 + counter)
            rows = dna_rows(rng, rng.randrange(40, 120), SITES_A, colspec)
            path = os.path.join(store, key)
            write_parquet(rows, columns, path)
            if schema_break_key == key:
                # same names, wrong order -> schema mismatch
                df = pd.read_parquet(path)
                df = df[list(reversed(columns))]
                df.to_parquet(path, index=False, engine="pyarrow")
            rows_per_file[key] = len(rows)
            entries.append({"key": key, "sha256": sha256(path)})
        manifest["splits"].append({"role": role, "files": entries})
    with open(os.path.join(store, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    if tamper_key:
        # rewrite one object with extra rows AFTER recording its sha
        path = os.path.join(store, tamper_key)
        df = pd.read_parquet(path)
        extra = df.head(5).copy()
        pd.concat([df, extra], ignore_index=True).to_parquet(
            path, index=False, engine="pyarrow")
    return manifest, rows_per_file


def expected_report(manifest, rows_per_file):
    rows = {}
    complete = {}
    total = 0
    files = 0
    for sp in manifest["splits"]:
        r = sp["role"]
        n = sum(rows_per_file[e["key"]] for e in sp["files"])
        rows[r] = n
        complete[r] = len(sp["files"]) >= 1
        total += n
        files += len(sp["files"])
    return {
        "dataset": manifest["dataset"],
        "version": manifest["version"],
        "columns": manifest["columns"],
        "files_downloaded": files,
        "total_rows": total,
        "rows": rows,
        "splits_complete": complete,
        "sha_ok": True,
        "schema_ok": True,
        "error": None,
    }


COLSPEC_A = [("site", "site"), ("observed_at", "date"), ("depth_cm", "int"),
             ("wind_kph", "int"), ("danger", "cat")]
COLSPEC_B = [("pit", "site"), ("sampled_at", "date"), ("height_cm", "int"),
             ("temp_c", "int"), ("grain", "cat")]
COLSPEC_C = [("slope", "site"), ("aspect", "cat"), ("depth_cm", "int")]
COLSPEC_D = [("station", "site"), ("logged_at", "date"), ("rime_mm", "int")]

# ---------------- visible store ----------------
man_v, rows_v = build(os.path.join(TASK, "environment/files/realm"), "cirque",
                      "cirque-avalanche-2024", "4",
                      ["site", "observed_at", "depth_cm", "wind_kph", "danger"],
                      COLSPEC_A, [("train", 3), ("val", 2), ("test", 2)],
                      seed=101)
json.dump(expected_report(man_v, rows_v),
          open(os.path.join(TASK, "tests/expected/visible.json"), "w"),
          indent=2)
open(os.path.join(TASK, "tests/expected/visible.json"), "a").write("\n")

HID = os.path.join(TASK, "tests/hidden")

# ---------------- hidden: moraine (normal success) ----------------
man, rows = build(os.path.join(HID, "moraine/store"), "moraine",
                  "moraine-snowpits-2025", "2",
                  ["pit", "sampled_at", "height_cm", "temp_c", "grain"],
                  COLSPEC_B, [("train", 4), ("val", 1), ("test", 3)], seed=202)
json.dump({"mode": "success", "bucket": "moraine",
           "report": expected_report(man, rows)},
          open(os.path.join(HID, "moraine/expected.json"), "w"), indent=2)
open(os.path.join(HID, "moraine/expected.json"), "a").write("\n")

# ---------------- hidden: windslab (no val split; still success) ----------------
man, rows = build(os.path.join(HID, "windslab/store"), "windslab",
                  "windslab-probe-2023", "1",
                  ["slope", "aspect", "depth_cm"],
                  COLSPEC_C, [("train", 2), ("test", 2)], seed=303)
json.dump({"mode": "success", "bucket": "windslab",
           "report": expected_report(man, rows)},
          open(os.path.join(HID, "windslab/expected.json"), "w"), indent=2)
open(os.path.join(HID, "windslab/expected.json"), "a").write("\n")

# ---------------- hidden: rime (tampered object -> sha mismatch) ----------------
man, rows = build(os.path.join(HID, "rime/store"), "rime",
                  "rime-stations-2022", "7",
                  ["station", "logged_at", "rime_mm"],
                  COLSPEC_D, [("train", 2), ("val", 1), ("test", 2)], seed=404,
                  tamper_key="test/part-001.parquet")
json.dump({"mode": "fail", "bucket": "rime",
           "sha_ok": False, "schema_ok": None,
           "error_contains": "sha-mismatch"},
          open(os.path.join(HID, "rime/expected.json"), "w"), indent=2)
open(os.path.join(HID, "rime/expected.json"), "a").write("\n")

# ---------------- hidden: hoarfrost (schema mismatch) ----------------
man, rows = build(os.path.join(HID, "hoarfrost/store"), "hoarfrost",
                  "hoarfrost-pits-2026", "3",
                  ["pit", "sampled_at", "height_cm", "temp_c", "grain"],
                  COLSPEC_B, [("train", 2), ("val", 2), ("test", 1)], seed=505,
                  schema_break_key="val/part-000.parquet")
json.dump({"mode": "fail", "bucket": "hoarfrost",
           "sha_ok": True, "schema_ok": False,
           "error_contains": "schema-mismatch"},
          open(os.path.join(HID, "hoarfrost/expected.json"), "w"), indent=2)
open(os.path.join(HID, "hoarfrost/expected.json"), "a").write("\n")

# ---------------- hidden: whiteout (missing manifest) ----------------
os.makedirs(os.path.join(HID, "whiteout/store"), exist_ok=True)
open(os.path.join(HID, "whiteout/expected.json"), "w").write(
    json.dumps({"mode": "fail", "bucket": "whiteout",
                "error_contains": "manifest"}, indent=2) + "\n")

print("drift-quarry fixtures generated")
