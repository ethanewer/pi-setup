#!/usr/bin/env python3
"""Enumerate fillable AcroForm fields of a PDF and emit a sorted JSON list of
{name, label}. label = the field's alternate name (/TU); falls back to the
field name when no alternate name is present.
Usage: parse_form.py <input.pdf> <output.json>
"""
import json, sys
from pypdf import PdfReader


def extract(pdf_path):
    reader = PdfReader(pdf_path)
    fields = reader.get_fields() or {}
    out = []
    for name, f in fields.items():
        label = f.get('/TU') or name
        out.append({"name": str(name), "label": str(label)})
    out.sort(key=lambda e: e["name"])
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: parse_form.py <input.pdf> <output.json>\n")
        sys.exit(2)
    result = extract(sys.argv[1])
    with open(sys.argv[2], "w") as fh:
        json.dump(result, fh, indent=2)
    print("parsed %d fields" % len(result))
