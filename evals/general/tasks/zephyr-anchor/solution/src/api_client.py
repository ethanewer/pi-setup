#!/usr/bin/env python3
"""api_client: query the localhost spectra/structure API and join project
membership to employee records.

Contract:
    python3 /app/api_client.py <data_dir> <out.json>

<data_dir> must contain:
    api.json       list of {"id","sequence","excitation_nm","emission_nm"}
    employees.json list of {"id","name","department"}
    projects.json  list of {"id","department","member_ids":[...]}
    spec.json      {"donor":{"emission_min","emission_max"},
                    "acceptor":{"excitation_min","excitation_max"},
                    "sequence_ids":[...], "project_ids":[...]}

Steps:
1. Start the local fixture server  python3 /app/api_server.py <data_dir>/api.json
   <port>  on a free 127.0.0.1 port and poll /healthz until ready.
2. For every protein in the DB, query GET /api/spectra?id=<id>. Choose
   donor  = the unique protein whose emission_nm lies in
            [donor.emission_min, donor.emission_max];
   acceptor = the unique protein whose excitation_nm lies in
            [acceptor.excitation_min, acceptor.excitation_max].
   The seed data guarantees exactly one protein satisfies each side (the two
   windows are disjoint and each selects a distinct protein).
3. For each sid in spec.sequence_ids, query GET /api/sequences?id=<sid> and
   record the returned amino-acid sequence unchanged.
4. For each pid in spec.project_ids, look up projects.json and resolve EVERY
   member_id against employees.json, keeping only employees whose department
   equals the project's department. Seed data guarantees every member resolves.

Writes <out.json>:
    {
      "donor":    {"id","excitation_nm","emission_nm"},
      "acceptor": {"id","excitation_nm","emission_nm"},
      "sequences": { "<id>": "<amino-acid sequence>" },
      "projects": {
          "<project id>": {
              "resolved_members": [
                  {"member_id","employee_id","name","department"} ],
              "unresolved_member_ids": []
          }
      }
    }
Exit status 0 on success. Never reads the verifier fixtures.
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

SERVER = "/app/api_server.py"
BASE = "http://127.0.0.1:%d"


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_server(api_path, port):
    proc = subprocess.Popen(
        [sys.executable, SERVER, api_path, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(120):
        try:
            with urllib.request.urlopen(
                    (BASE % port) + "/health", timeout=0.4) as r:
                if r.status == 200:
                    return proc
        except Exception:
            time.sleep(0.1)
    proc.terminate()
    raise RuntimeError("fixture server did not become ready")


def get_json(url):
    with urllib.request.urlopen(url, timeout=5) as r:
        return json.load(r)


def load(path):
    with open(path) as fh:
        return json.load(fh)


def run(data_dir, out_path):
    api_path = os.path.join(data_dir, "api.json")
    spec = load(os.path.join(data_dir, "spec.json"))
    employees = load(os.path.join(data_dir, "employees.json"))
    projects = load(os.path.join(data_dir, "projects.json"))
    db = load(api_path)

    port = free_port()
    proc = start_server(api_path, port)
    try:
        donor = None
        acceptor = None
        for rec in db:
            sp = get_json((BASE % port) + "/api/spectra?id=" + rec["id"])
            if spec["donor"]["emission_min"] <= sp["emission_nm"] <= \
                    spec["donor"]["emission_max"]:
                donor = sp
            if spec["acceptor"]["excitation_min"] <= sp["excitation_nm"] <= \
                    spec["acceptor"]["excitation_max"]:
                acceptor = sp

        sequences = {}
        for sid in spec["sequence_ids"]:
            sequences[sid] = get_json(
                (BASE % port) + "/api/sequences?id=" + sid)["sequence"]

        emp_by_id = {e["id"]: e for e in employees}
        proj_by_id = {p["id"]: p for p in projects}
        project_out = {}
        for pid in spec["project_ids"]:
            proj = proj_by_id[pid]
            resolved = []
            unresolved = []
            for member in proj["member_ids"]:
                emp = emp_by_id.get(member)
                if emp and emp["department"] == proj["department"]:
                    resolved.append({
                        "member_id": member,
                        "employee_id": emp["id"],
                        "name": emp["name"],
                        "department": emp["department"],
                    })
                else:
                    unresolved.append(member)
            project_out[pid] = {
                "resolved_members": resolved,
                "unresolved_member_ids": unresolved,
            }

        report = {
            "donor": donor,
            "acceptor": acceptor,
            "sequences": sequences,
            "projects": project_out,
        }
        with open(out_path, "w") as fh:
            json.dump(report, fh, indent=2)
        return 0
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=3)
        except Exception:
            proc.kill()


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: api_client.py <data_dir> <out.json>\n")
        return 2
    return run(argv[1], argv[2])


if __name__ == "__main__":
    sys.exit(main(sys.argv))