#!/usr/bin/env python3
"""URL-normalizer verifier for fern-hearth.

Runs /app/normalize_url.py on each hidden URL input from /tests/hidden and checks
the output against the independent canonical form. Also verifies the agent's own
/app/urls.tsv is fully canonicalized (normalize idempotent).
"""
import os
import subprocess
import sys

sys.path.insert(0, "/tests/helpers")
import canonical  # noqa: E402

NORMALIZER = "/app/normalize_url.py"
HIDDEN_DIR = "/tests/hidden"


def run_normalizer(infile):
    r = subprocess.run(["python3", NORMALIZER, infile], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("normalize_url.py rc=%s: %s"
                           % (r.returncode, r.stderr.decode(errors="replace")))
    text = r.stdout.decode("utf-8", errors="replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def check_hidden(name, failures):
    infile = os.path.join(HIDDEN_DIR, name)
    with open(infile, encoding="utf-8") as f:
        expect = canonical.normalize_lines(f.read())
    try:
        actual = run_normalizer(infile)
    except RuntimeError as e:
        failures.append("hidden %s: %s" % (name, e))
        return
    if len(actual) != len(expect):
        failures.append("hidden %s: line count %d != %d"
                        % (name, len(actual), len(expect)))
        return
    for i, (e, a) in enumerate(zip(expect, actual)):
        if a != e:
            failures.append("hidden %s line %d: got %r want %r"
                            % (name, i, a, e))


def main():
    failures = []
    for fn in sorted(os.listdir(HIDDEN_DIR)):
        if fn.startswith("urls_") and fn.endswith(".txt"):
            check_hidden(fn, failures)

    if not os.path.isfile("/app/urls.tsv"):
        failures.append("missing /app/urls.tsv")
    else:
        with open("/app/urls.tsv", encoding="utf-8") as f:
            lines = [ln.strip() for ln in f.read().split("\n")
                     if ln.strip() != ""]
        if not lines:
            failures.append("urls.tsv is empty")
        for ln in lines:
            if canonical.canonicalize(ln) != ln:
                failures.append("urls.tsv line not canonical: %r" % ln)

    if failures:
        for f in failures:
            print("FAIL: %s" % f)
        sys.exit(1)
    print("URLS-OK")
    sys.exit(0)


if __name__ == "__main__":
    main()