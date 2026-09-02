#!/usr/bin/env python3
"""larch-dial solver: drive a fixture tree to green and emit a report JSON.

CLI (exactly four arguments, all paths, in this order):

    python3 solve.py FIXTURE WEIGHTS INPUTS OUTPUT

  FIXTURE : directory whose subtree is:
         config/main.txt        fixed frame, contains an @@INCLUDE@@ line
         config/synonyms.txt    permitted synonym map, one `key=value` per line
         config/incr.txt        the subordinate include file to edit in place
         suite/                 focused pytest suite (must be driven to green)
         cap.txt                maximum allowed length of the report sequence
  WEIGHTS : a flat JSON object mapping family -> weight (float)
  INPUTS  : a CSV file, `family,count,warp` rows (may carry blank/#comment rows
            and malformed records, which are skipped)
  OUT     : where the report JSON is written

Report contract:
  fscore           = round(sum(count * warp * weight[family]), 3)
  pass_count       = number of passing pytest tests in FIXTURE/suite
  sequence         = sha256 hex of the edited include text (exactly cap chars)
  edited_sha256    = sha256 hex of the edited include text
  compiled_sha256  = sha256 hex of the rendered frame with the edited include
                     inlined at the INCLUDE marker
  cap              = integer ceiling read from cap.txt
All inputs come from argv; nothing is hard-coded. Only the stdlib is used.
"""
import csv
import hashlib
import json
import os
import re
import subprocess
import sys

INCLUDE_MARKER = "@@INCLUDE@@"


def load_synonyms(path):
    keep = {}
    with open(path, "r") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            keep[key.strip()] = val.strip()
    return keep


def substitute(word, keep):
    """Replace a white-space token by a permitted synonym when it appears in
    the map, preserving any surrounding punctuation; other tokens are left
    untouched."""
    pre, post = "", ""
    w = word
    while w and not w[0].isalnum():
        pre += w[0]
        w = w[1:]
    while w and not w[-1].isalnum():
        post = w[-1] + post
        w = w[:-1]
    if not pre and not post and w in keep:
        return keep[w]
    if w in keep:
        return pre + keep[w] + post
    return pre + w + post


def edit_include(cfg_dir, keep):
    with open(os.path.join(cfg_dir, "incr.txt"), "r") as fh:
        lines = fh.read().splitlines()
    edited = []
    for line in lines:
        edited.append(" ".join(substitute(t, keep) for t in line.split()))
    edited_text = "\n".join(edited)
    with open(os.path.join(cfg_dir, "incr.edited.txt"), "w") as fh:
        fh.write(edited_text + "\n")
    return edited_text


def render_compiled(cfg_dir, edited_text):
    with open(os.path.join(cfg_dir, "main.txt"), "r") as fh:
        frame = fh.read().splitlines()
    out = []
    for line in frame:
        if line.strip() == INCLUDE_MARKER:
            out.append(edited_text)
        else:
            out.append(line)
    compiled = "\n".join(out)
    with open(os.path.join(cfg_dir, "compiled.txt"), "w") as fh:
        fh.write(compiled + "\n")
    return compiled


def compute_fscore(weights, inputs_path):
    total = 0.0
    with open(inputs_path, newline="") as fh:
        for row in csv.reader(fh):
            if len(row) != 3:
                continue
            fam, cnt, warp = (c.strip() for c in row)
            try:
                cnt = float(cnt)
                warp = float(warp)
            except ValueError:
                continue
            w = weights.get(fam, 0.0)
            total += warp * cnt * w
    return round(total, 3)


def run_suite(fixture):
    suite = os.path.join(fixture, "suite")
    r = subprocess.run(
        ["python3", "-m", "pytest", "--tb=no", "-q", suite],
        cwd=fixture, capture_output=True, text=True)
    m = re.search(r"(\d+)\s+passed", r.stdout or "")
    return int(m.group(1)) if m else -1, r.returncode


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main():
    if len(sys.argv[1:]) != 4:
        sys.exit("usage: solve.py <FIXTURE> <WEIGHTS> <INPUTS> <OUT>")
    fixture, weights_path, inputs_path, out_path = sys.argv[1:]

    weights = json.load(open(weights_path))
    fscore = compute_fscore(weights, inputs_path)

    cfg = os.path.join(fixture, "config")
    keep = load_synonyms(os.path.join(cfg, "synonyms.txt"))
    edited_text = edit_include(cfg, keep)
    compiled_text = render_compiled(cfg, edited_text)

    with open(os.path.join(fixture, "cap.txt")) as fh:
        cap = int(fh.read().strip())

    pass_count, rc = run_suite(fixture)

    with open(os.path.join(cfg, "main.txt")) as fh:
        main_text = fh.read()
    with open(os.path.join(cfg, "synonyms.txt")) as fh:
        syn_text = fh.read()

    sequence = sha(edited_text)
    report = {
        "fscore": fscore,
        "pass_count": pass_count,
        "sequence": sequence,
        "edited_sha256": sequence,
        "compiled_sha256": sha(compiled_text),
        "cap": cap,
        "main_sha256": sha(main_text),
        "synonyms_sha256": sha(syn_text),
        "suite_exit": rc,
    }
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    print("fscore=%.3f pass=%d seqlen=%d cap=%d" %
          (fscore, pass_count, len(sequence), cap))


if __name__ == "__main__":
    main()