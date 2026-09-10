#!/usr/bin/env python3
"""Per-case assertions for the derrick-tarn picdrome verifier.

Usage: check_case.py <case-dir> <out-dir> <meta-json>

<case-dir> must contain expected.json and site/ (the mock docroot served for
this case). <out-dir> must contain the gallery-dl download output and <meta-json> must
be the captured stdout of `gallery-dl -j` for the same URL.

Asserts, for one hidden gallery:
  1. the downloaded file NAMES are exactly the basenames of the linked media
     files (one file per media link),
  2. each downloaded file's BYTES are identical to the served media file,
  3. the `gallery-dl -j` output contains a picdrome gallery record whose
     `title` and `count` match the fixture.
Exits 0 only if all three hold for this case.
"""
import json
import os
import sys


def files_under(root):
    files = {}
    for dirpath, _dirnames, names in os.walk(root):
        for name in names:
            files[name] = os.path.join(dirpath, name)
    return files


def main():
    case_dir, out_dir, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(os.path.join(case_dir, "expected.json"), encoding="utf-8") as fp:
        exp = json.load(fp)

    errors = []

    # ---- 1. filenames ---------------------------------------------------
    found = files_under(out_dir)
    expected_names = {os.path.basename(m) for m in exp["media"]}
    got_names = set(found)
    if got_names != expected_names:
        errors.append(
            "filenames: expected %s, found %s"
            % (sorted(expected_names), sorted(got_names)))

    # ---- 2. bytes --------------------------------------------------------
    else:
        for media in exp["media"]:
            fname = os.path.basename(media)
            src = os.path.join(case_dir, "site", media.lstrip("/"))
            got = open(found[fname], "rb").read()
            want = open(src, "rb").read()
            if got != want:
                errors.append(
                    "bytes of %s: downloaded %d bytes, fixture has %d bytes"
                    % (fname, len(got), len(want)))

    # ---- 3. metadata from `gallery-dl -j` ---------------------------------
    if not os.path.exists(meta_path):
        errors.append("meta.json missing (run of `gallery-dl -j` produced no "
                      "captured stdout)")
    else:
        with open(meta_path, encoding="utf-8") as fp:
            meta = json.load(fp)
        gallery = None
        for row in meta:
            if (isinstance(row, list) and len(row) == 2
                    and isinstance(row[1], dict)
                    and row[1].get("category") == "picdrome"):
                gallery = row[1]
                break
        if gallery is None:
            errors.append("no picdrome gallery record in `gallery-dl -j` "
                          "output (raw: %s)" % str(meta)[:200])
        else:
            if gallery.get("title") != exp["title"]:
                errors.append("title: %r != %r"
                              % (gallery.get("title"), exp["title"]))
            if gallery.get("count") != exp["num_media"]:
                errors.append("count: %r != %r"
                              % (gallery.get("count"), exp["num_media"]))

    if errors:
        case = os.path.basename(case_dir)
        print("FAIL %s: %s" % (case, " ; ".join(errors)), flush=True)
        sys.exit(1)

    print("PASS %s" % os.path.basename(case_dir), flush=True)
    sys.exit(0)


if __name__ == "__main__":
    main()