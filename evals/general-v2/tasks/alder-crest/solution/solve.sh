#!/bin/bash
# Real oracle for alder-crest: write the solve.py program, then RUN it on the
# shipped paper to produce /app/compiled.tex and /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'PY'
import hashlib
import json
import sys

PUNCT = ".,;:!?'\"()"


def load_map(path):
    m = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            k, _, v = s.partition("=")
            m[k.strip()] = v.strip()
    return m


def edit_body(body_text, syn):
    out, reps = [], 0
    for tok in body_text.split():
        core = tok.strip(PUNCT)
        lead = tok[:len(tok) - len(tok.lstrip(PUNCT))]
        trail = tok[len(tok.rstrip(PUNCT)):]
        hit = None
        for k, v in syn.items():
            if k.lower() == core.lower():
                hit = v
                break
        if hit is None or core == "":
            out.append(tok)
            continue
        if core.isupper() and len(core) > 1:
            rep = hit.upper()
        elif core[:1].isupper():
            rep = hit.capitalize()
        else:
            rep = hit.lower()
        out.append(lead + rep + trail)
        reps += 1
    return " ".join(out), reps


def main():
    press_dir, compiled_out, report_out = sys.argv[1], sys.argv[2], sys.argv[3]
    frame = open(press_dir + "/frame.tex", encoding="utf-8").read()
    amap = open(press_dir + "/allowed.map", encoding="utf-8").read()
    body = open(press_dir + "/body_chapter.tex", encoding="utf-8").read()
    syn = load_map(press_dir + "/allowed.map")
    edited, reps = edit_body(body, syn)
    edited = edited.rstrip("\n")
    compiled = frame.replace("%%INCLUDE-BODY%%", edited)
    with open(compiled_out, "w", encoding="utf-8") as fh:
        fh.write(compiled)
    report = {
        "edited_sha256": hashlib.sha256(edited.encode()).hexdigest(),
        "compiled_sha256": hashlib.sha256(compiled.encode()).hexdigest(),
        "frame_sha256": hashlib.sha256(frame.encode()).hexdigest(),
        "map_sha256": hashlib.sha256(amap.encode()).hexdigest(),
        "replacements": reps,
    }
    with open(report_out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/press /app/compiled.tex /app/answer.json

echo "solve.sh done -> $SOLVER /app/compiled.tex /app/answer.json"
ls -l "$SOLVER" /app/compiled.tex /app/answer.json
