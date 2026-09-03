#!/usr/bin/env python3
"""analyze_xxe: probe every parser in a parsers directory with crafted
payloads inside a sandboxed temp directory and emit a deterministic
per-parser audit.

Usage:
    python3 analyze_xxe.py [--parsers-dir DIR] [--out FILE] [--max-depth N]

Defaults: parsers-dir=/app/parsers, out=/app/xxe_audit.json, max-depth=6.

Probes (both built fresh in the sandbox temp dir; marker character '#'):
  * file-read probe: a document declaring <!ENTITY xxe SYSTEM "file://...">
    that references a local secret file written by this analyzer. A parser
    is vulnerable to "external entity resolution" when the secret bytes show
    up in its stdout.
  * recursive probe: an internal general-entity chain of depth
    max_depth + 4. A parser is vulnerable to "recursive entity expansion"
    when it exits 0 and its stdout contains a contiguous marker run longer
    than 2 ** max_depth.

Verdict classes use the exact vocabulary in /app/config.json. The output
lists parsers in sorted filename order and is fully deterministic.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PARSER_NAMES = [
    "catalog_fetch.py",
    "directive_loader.py",
    "plain_text.py",
    "report_sieve.py",
    "snippet_extract.py",
]
CANONICAL = {
    "external": "external entity resolution",
    "recursive": "recursive entity expansion",
}
SECRET = "BRIAR-ANALYZER-SECRET-9137"
MARKER = "#"


def build_probes(tmp, depth):
    secret = os.path.join(tmp, "secret.txt")
    with open(secret, "w", encoding="utf-8") as handle:
        handle.write(SECRET + "\n")
    file_probe = os.path.join(tmp, "file_probe.xml")
    with open(file_probe, "w", encoding="utf-8") as handle:
        handle.write(
            '<?xml version="1.0"?>\n'
            '<!DOCTYPE r [<!ENTITY xxe SYSTEM "%s">]>\n'
            '<r>pre &xxe; post</r>\n' % Path(secret).as_uri())
    rec_probe = os.path.join(tmp, "rec_probe.xml")
    lines = ['<?xml version="1.0"?>', "<!DOCTYPE deep [",
             '<!ENTITY e0 "%s">' % MARKER]
    for i in range(1, depth + 1):
        lines.append('<!ENTITY e%d "&e%d;&e%d;">' % (i, i - 1, i - 1))
    lines.append("]>")
    lines.append("<deep>&e%d;</deep>" % depth)
    with open(rec_probe, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    return file_probe, rec_probe


def run_parser(parser_path, probe):
    try:
        result = subprocess.run(
            [sys.executable, str(parser_path), probe],
            capture_output=True, timeout=60)
        return result.returncode, result.stdout
    except Exception:
        return -1, b""


def probe_parser(parser_path, file_probe, rec_probe, max_depth):
    classes = []
    _, file_out = run_parser(parser_path, file_probe)
    if SECRET.encode("utf-8") in file_out:
        classes.append(CANONICAL["external"])
    rec_rc, rec_out = run_parser(parser_path, rec_probe)
    if rec_rc == 0 and re.search(
            (MARKER * (2 ** max_depth + 1)).encode("utf-8"),
            rec_out):
        classes.append(CANONICAL["recursive"])
    return sorted(set(classes))


def audit(parsers_dir, max_depth):
    dir_path = Path(parsers_dir)
    found = {}
    for name in PARSER_NAMES:
        path = dir_path / name
        if path.is_file():
            found[name] = path
    entries = []
    with tempfile.TemporaryDirectory(prefix="analyze-xxe-") as tmp:
        file_probe, rec_probe = build_probes(tmp, max_depth + 4)
        for name in sorted(found):
            classes = probe_parser(found[name], file_probe, rec_probe,
                                   max_depth)
            entries.append({
                "parser": name,
                "vulnerable": bool(classes),
                "reasons": classes,
            })
    return {
        "schema": "raven-core/audit/v1",
        "max_entity_depth": max_depth,
        "generated_by": "analyze_xxe.py",
        "parsers": entries,
    }


def main(argv):
    parser = argparse.ArgumentParser(prog=os.path.basename(__file__))
    parser.add_argument("--parsers-dir", default="/app/parsers")
    parser.add_argument("--out", default="/app/xxe_audit.json")
    parser.add_argument("--max-depth", type=int, default=6)
    args = parser.parse_args(argv[1:])
    payload = audit(args.parsers_dir, args.max_depth)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("analyze_xxe: wrote %s (%d parser(s))"
          % (out, len(payload["parsers"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))