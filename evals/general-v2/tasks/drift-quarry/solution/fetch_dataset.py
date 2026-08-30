#!/usr/bin/env python3
"""Drift Quarry — dataset fetcher for the Cirque object store.

python3 fetch_dataset.py --endpoint URL --bucket NAME --out DIR
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.request


def fail(report, out_dir, msg, code=1):
    if report is not None and out_dir is not None:
        write_report(report, out_dir)
    print("ERROR: %s" % msg, file=sys.stderr)
    sys.exit(code)


def write_report(report, out_dir):
    try:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "report.json"), "w") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
    except Exception:
        pass


def fetch(url, timeout=30):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    endpoint = args.endpoint.rstrip("/")
    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)

    report = {
        "dataset": None, "version": None, "columns": [],
        "files_downloaded": 0, "total_rows": 0, "rows": {},
        "splits_complete": {}, "sha_ok": True, "schema_ok": True,
        "error": None,
    }

    # ---- manifest ----
    import pandas as pd
    try:
        raw = fetch("%s/%s/manifest.json" % (endpoint, args.bucket))
        manifest = json.loads(raw.decode("utf-8"))
    except Exception as e:
        report["error"] = "manifest-unreachable:%s" % e
        fail(report, out_dir, "cannot fetch manifest: %s" % e, 2)
    if not isinstance(manifest, dict) or any(
            k not in manifest for k in ("dataset", "version", "columns",
                                        "splits")):
        report["error"] = "manifest-malformed"
        fail(report, out_dir, "manifest malformed or missing fields", 2)
    columns = manifest["columns"]
    splits = manifest["splits"]
    report["dataset"] = manifest["dataset"]
    report["version"] = manifest["version"]
    report["columns"] = list(columns)
    for sp in splits:
        report["rows"].setdefault(sp["role"], 0)
        report["splits_complete"][sp["role"]] = len(sp.get("files", [])) >= 1

    if not any(sp["role"] == "train" and sp["files"] for sp in splits):
        report["error"] = "missing-split:train"
        fail(report, out_dir, "split availability failure: no train files")
    if not any(sp["role"] == "test" and sp["files"] for sp in splits):
        report["error"] = "missing-split:test"
        fail(report, out_dir, "split availability failure: no test files")

    # ---- download + verify ----
    frames = {sp["role"]: [] for sp in splits}
    total_files = 0
    for sp in splits:
        role = sp["role"]
        for entry in sp["files"]:
            key = entry["key"]
            want_sha = entry["sha256"]
            dest = os.path.join(out_dir, key)
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            try:
                blob = fetch("%s/%s/%s" % (endpoint, args.bucket, key))
            except Exception as e:
                report["error"] = "download-failed:%s" % key
                fail(report, out_dir, "download failed for %s: %s" % (key, e))
            with open(dest, "wb") as fh:
                fh.write(blob)
            got = hashlib.sha256(blob).hexdigest()
            if got != want_sha:
                report["sha_ok"] = False
                report["error"] = "sha-mismatch:%s" % key
                fail(report, out_dir,
                     "sha256 mismatch for %s (want %s got %s)"
                     % (key, want_sha, got))
            try:
                df = pd.read_parquet(dest)
            except Exception as e:
                report["error"] = "parquet-unreadable:%s" % key
                fail(report, out_dir, "unreadable parquet %s: %s" % (key, e))
            if list(df.columns) != list(columns):
                report["schema_ok"] = False
                report["error"] = "schema-mismatch:%s" % key
                fail(report, out_dir,
                     "schema mismatch for %s: %s != %s"
                     % (key, list(df.columns), list(columns)))
            frames[role].append(df)
            report["files_downloaded"] += 1
            report["rows"][role] = report["rows"].get(role, 0) + len(df)
            report["total_rows"] += len(df)
            total_files += 1

    # ---- concatenate per role ----
    for sp in splits:
        role = sp["role"]
        if frames[role]:
            pd.concat(frames[role], ignore_index=True).to_parquet(
                os.path.join(out_dir, "%s.parquet" % role),
                index=False, engine="pyarrow")

    report["error"] = None
    write_report(report, out_dir)
    print("FETCH_OK files=%d rows=%d"
          % (report["files_downloaded"], report["total_rows"]))
    sys.exit(0)


if __name__ == "__main__":
    main()
