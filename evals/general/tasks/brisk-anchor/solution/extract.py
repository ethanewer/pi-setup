#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract structured profile facts (name/email/phone/zip) from documents.

Usage: python3 /app/extract.py [input_dir] [output_json]
Defaults: input /app/docs , output /app/profiles.json
Output = [ {"doc": filename, "name": str|null, "email": str|null,
            "phone": str|null, "zip": str|null}, ... ] sorted by doc.
Company label capture: the word Name (case-insensitive) followed by ":=" and a
run of 2-4 capitalised tokens on the same line."""
import json, os, re, sys

RE_NAME = re.compile(r"\bName\s*[:=]\s*([A-Z][A-Za-z'.-]*(?:[ \t]+[A-Z][A-Za-z'.-]*){1,3})", re.I)
RE_EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
RE_PHONE = re.compile(r"((?:\+?\d{1,2}[\s-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4})")
RE_ZIP = re.compile(r"\b(\d{5}(?:-\d{4})?)\b")

def profile_from(text):
    n = RE_NAME.search(text)
    e = RE_EMAIL.search(text)
    p = RE_PHONE.search(text)
    z = RE_ZIP.search(text)
    return {
        "name": n.group(1).strip() if n else None,
        "email": e.group(0) if e else None,
        "phone": p.group(1) if p else None,
        "zip": z.group(1) if z else None,
    }

def scan_dir(input_dir):
    out = []
    for n in sorted(os.listdir(input_dir)):
        if not n.endswith(".txt"):
            continue
        text = open(os.path.join(input_dir, n)).read()
        rec = profile_from(text)
        out.append({"doc": n, **rec})
    return out

def main():
    input_dir = sys.argv[1] if len(sys.argv) > 1 else "/app/docs"
    out_json = sys.argv[2] if len(sys.argv) > 2 else "/app/profiles.json"
    with open(out_json, "w") as fh:
        json.dump(scan_dir(input_dir), fh, indent=2)

if __name__ == "__main__":
    main()