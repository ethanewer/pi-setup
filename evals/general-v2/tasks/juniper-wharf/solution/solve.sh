#!/bin/bash
# juniper-wharf oracle: write every deliverable as real artifacts, then produce
# output by RUNNING that work against the live (already-served) fixtures.
set -euo pipefail
cd /app

# ---------------------------------------------------------------- 1. service.proto
cat > /app/service.proto <<'PROTO'
// service.proto -- Juniper Wharf registry RPC surface.
// The moorings data plane claims and renews dock berths against this contract.
syntax = "proto3";
package juniperwharf;

// A request to claim or renew a dock berth.
message DockRequest {
  string dock_id = 1;
  string vessel = 2;
  int32 berth = 3;
  map<string, string> labels = 4;
}

// The certificate/lease returned after a successful claim.
message Receipt {
  string receipt_id = 1;
  string dock_id = 2;
  string state = 3;
  int64 granted_at_ms = 4;
}

// The lease extension granted by a renewal.
message Renewal {
  int64 granted_at_ms = 1;
  int32 extend_minutes = 2;
  string token = 3;
}

// Registry service: two RPCs over the moorings dock plan.
service WharfRegistry {
  rpc Claim(DockRequest) returns (Receipt);
  rpc Renew(DockRequest) returns (Renewal);
}
PROTO

# compile it to prove the codegen works end-to-end
mkdir -p /tmp/gen
python3 -m grpc_tools.protoc -I/app --python_out=/tmp/gen --grpc_python_out=/tmp/gen /app/service.proto

# ---------------------------------------------------------------- 2. certcheck.py
cat > /app/certcheck.py <<'PY'
#!/usr/bin/env python3
"""TLS certificate metadata checker for Juniper Wharf.
Usage: python3 certcheck.py [CERT_PATH]   (default /app/juniper-tls.pem)
Prints CN=<CommonName|first DNS SAN>, EXPIRES=<UTC ISO-8601>, CHECK_STATUS=<OK|FAIL>.
"""
import datetime
import sys

try:
    from cryptography import x509
    from cryptography.hazmat.backends import default_backend
except Exception as e:  # pragma: no cover
    print("CN=")
    print("EXPIRES=")
    print("CHECK_STATUS=<FAIL> deps-missing")
    sys.exit(2)

path = sys.argv[1] if len(sys.argv) > 1 else "/app/juniper-tls.pem"


def main():
    try:
        with open(path, "rb") as fh:
            crt = x509.load_pem_x509_certificate(fh.read(), default_backend())
    except Exception:
        print("CN=")
        print("EXPIRES=")
        print("CHECK_STATUS=<FAIL> load-error")
        return 2

    attrs = crt.subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)
    cn = attrs[0].value if attrs else None
    if not cn:
        # fall back to first DNS SAN (no CN certificates)
        try:
            san = crt.extensions.get_extension_for_class(x509.SubjectAlternativeName)
            dns = san.value.get_values_for_type(x509.DNSName)
            cn = dns[0] if dns else ""
        except Exception:
            cn = ""

    exp = crt.not_valid_after_utc
    now = datetime.datetime.now(datetime.timezone.utc)
    status = "OK" if exp > now else "FAIL"
    print("CN=%s" % cn)
    print("EXPIRES=%s" % exp.strftime("%Y-%m-%dT%H:%M:%SZ"))
    print("CHECK_STATUS=%s" % status)
    return 0 if status == "OK" else 1


if __name__ == "__main__":
    main()
PY
python3 /app/certcheck.py /app/juniper-tls.pem > /app/cert_report.txt

# ---------------------------------------------------------------- 3. download.py
cat > /app/download.py <<'PY'
#!/usr/bin/env python3
"""Split dataset fetcher for the Juniper Wharf object store.
Usage: python3 download.py --endpoint http://127.0.0.1:9000 --bucket moorings --out DIR
Reads manifest.json, downloads every parquet split, validates SHA-256 + schema,
assembles train/val/test locally, writes report.json and a DOWNLOAD_OK line.
"""
import argparse
import hashlib
import json
import os
import sys

import pandas as pd
import requests


def fetch(url):
    r = requests.get(url, timeout=60)
    r.raise_for_status()
    return r.content


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    base = a.endpoint.rstrip("/") + "/" + a.bucket
    os.makedirs(a.out, exist_ok=True)

    manifest = json.loads(fetch(base + "/manifest.json"))
    cols = manifest["columns"]
    files = manifest["files"]

    if not any(f["role"] == "train" for f in files) or not any(
            f["role"] == "test" for f in files):
        print("ERROR: manifest lacks a train and a test split")
        sys.exit(1)

    downloaded = 0
    rows = {"train": 0, "val": 0, "test": 0}
    frames = {"train": [], "val": [], "test": []}

    for f in files:
        key = f["key"]
        role = f["role"]
        raw = fetch(base + "/" + key)
        if sha(raw) != f["sha256"]:
            print("ERROR sha mismatch for %s" % key)
            sys.exit(1)
        dest = os.path.join(a.out, key)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(raw)
        df = pd.read_parquet(dest)
        if list(df.columns) != cols:
            print("ERROR: column schema mismatch for %s" % key)
            sys.exit(1)
        rows[role] += len(df)
        frames[role].append(df)
        downloaded += 1

    for role in ("train", "val", "test"):
        if frames[role]:
            merged = pd.concat(frames[role], ignore_index=True)
            merged.to_parquet(os.path.join(a.out, role + ".parquet"), index=False)

    total = sum(rows.values())
    report = {
        "dataset": manifest["dataset"],
        "downloaded_files": downloaded,
        "sha_ok": True,
        "total_rows": total,
        "train_rows": rows["train"],
        "val_rows": rows["val"],
        "test_rows": rows["test"],
        "columns": cols,
        "splits_complete": True,
    }
    with open(os.path.join(a.out, "report.json"), "w") as fh:
        json.dump(report, fh)
    print("DOWNLOAD_OK files=%d rows=%d sha_ok=true" % (downloaded, total))


if __name__ == "__main__":
    main()
PY
rm -rf /app/wharf_train
python3 /app/download.py --endpoint http://127.0.0.1:9000 --bucket moorings --out /app/wharf_train

# ---------------------------------------------------------------- 4. creds_probe.py
cat > /app/creds_probe.py <<'PY'
#!/usr/bin/env python3
"""Honest default-credential probe for the Juniper Wharf control head.
usage: python3 creds_probe.py --control http://127.0.0.1:9001 [--access-key A] [--secret-key S]
Reports CREDS_REACHABLE=1 and minted credentials on a real 200; reports 0 and no
creds when the default pair is rejected (401 / unreachable). Never fabricates.
"""
import argparse
import base64
import json
import urllib.error
import urllib.request

OUT = "/app/probe_result.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--control", required=True)
    ap.add_argument("--access-key", default="wharfmaster")
    ap.add_argument("--secret-key", default="wharfmaster")
    a = ap.parse_args()

    url = a.control.rstrip("/") + "/v1/mint"
    tok = base64.b64encode((a.access_key + ":" + a.secret_key).encode()).decode()
    req = urllib.request.Request(url, headers={"Authorization": "Basic " + tok})

    body = None
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 200:
            try:
                body = json.loads(e.read().decode())
            except Exception:
                body = None
        else:
            body = None
    except Exception:
        body = None

    if body and body.get("access_key"):
        result = {"reachable": True,
                  "access_key": body["access_key"],
                  "secret_key": body["secret_key"],
                  "role": body.get("role")}
        print("CREDS_REACHABLE=1")
        print("CREDS_ACCESS_KEY=%s" % result["access_key"])
        print("CREDS_SECRET_KEY=%s" % result["secret_key"])
        print("CREDS_ROLE=%s" % result["role"])
    else:
        result = {"reachable": False,
                  "access_key": None, "secret_key": None, "role": None}
        print("CREDS_REACHABLE=0")

    with open(OUT, "w") as fh:
        json.dump(result, fh)


if __name__ == "__main__":
    main()
PY
python3 /app/creds_probe.py --control http://127.0.0.1:9001 --access-key wharfmaster --secret-key wharfmaster > /app/probe_report.txt

echo "ORACLE DONE"
ls -la /app/service.proto /app/certcheck.py /app/download.py /app/creds_probe.py