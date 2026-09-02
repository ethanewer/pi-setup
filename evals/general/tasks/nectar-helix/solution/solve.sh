#!/bin/bash
# Oracle for the nectar-helix task.
#
# REAL solution: authors the three /app tool utilities and then RUNS each one
# on the shipped fixtures to build the visible output trees. Never reads /tests
# and never emits a precomputed answer.
set -eu

# ---------------- Tool 1: mk_leafs.py ----------------
cat > /app/mk_leafs.py <<'PYEOF'
#!/usr/bin/env python3
"""Instantiate the tree of a listing as zero-byte leaves.

    python3 mk_leafs.py --listing <listing.txt> --outdir <dir>
"""
import argparse
import os
import sys


def parse_entries(listing):
    with open(listing, 'r', encoding='utf-8', errors='surrogateescape') as fh:
        lines = fh.read().splitlines()
    entries = []
    for line in lines:
        s = line.strip()
        if not s:
            continue
        if s[0] == '#':
            continue
        is_dir = s.endswith('/')
        body = s[:-1] if is_dir else s
        if body == "":
            raise ValueError("empty path in entry: %r" % s)
        if body.startswith('/') or body.startswith('\\'):
            raise ValueError("absolute path not allowed: %r" % s)
        if body == '..' or body.startswith('../') or '/../' in body \
                or body.endswith('/..'):
            raise ValueError("'..' component not allowed: %r" % s)
        entries.append((body, is_dir))
    return entries


def main(argv):
    ap = argparse.ArgumentParser(prog='mk_leafs.py')
    ap.add_argument('--listing', required=True)
    ap.add_argument('--outdir', required=True)
    a = ap.parse_args(argv)
    try:
        entries = parse_entries(a.listing)
        base = a.outdir
        os.makedirs(base, exist_ok=True)
        for body, is_dir in entries:
            target = os.path.join(base, body)
            if is_dir:
                if os.path.isfile(target):
                    raise ValueError("dir '%s' collides with a file" % body)
                os.makedirs(target, exist_ok=True)
                continue
            if os.path.isdir(target):
                raise ValueError("file '%s' collides with a directory" % body)
            dirname = os.path.dirname(target)
            if dirname:
                if os.path.isfile(dirname):
                    raise ValueError("parent of '%s' is a file" % body)
                os.makedirs(dirname, exist_ok=True)
            if not os.path.exists(target):
                with open(target, 'wb'):
                    pass
    except (OSError, ValueError) as exc:
        print("mk_leafs error: %s" % exc, file=sys.stderr)
        return 2
    print("mk_leafs: created %d leaf(s) under %s" % (len(entries), a.outdir))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
PYEOF
chmod +x /app/mk_leafs.py

# ---------------- Tool 2: reshard.py ----------------
cat > /app/reshard.py <<'PYEOF'
#!/usr/bin/env python3
"""Repack a source tree into an output tree capping per-dir item count and
per-file byte budget.

    python3 reshard.py --input <dir> --output <dir> --max-items N --max-bytes B
"""
import argparse
import math
import os
import shutil
import sys


def gather(src):
    files = []
    for root, dirs, fs in os.walk(src):
        dirs.sort()
        for f in sorted(fs):
            ab = os.path.join(root, f)
            if os.path.isfile(ab):
                files.append((os.path.relpath(ab, src), ab))
    files.sort(key=lambda t: t[0])
    return files


def main(argv):
    ap = argparse.ArgumentParser(prog='reshard.py')
    ap.add_argument('--input', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--max-items', required=True)
    ap.add_argument('--max-bytes', required=True)
    a = ap.parse_args(argv)
    try:
        n = int(a.max_items)
        b = int(a.max_bytes)
    except ValueError:
        print("reshard error: --max-items/--max-bytes must be integers",
              file=sys.stderr)
        return 2
    if n < 1 or b < 1:
        print("reshard error: --max-items and --max-bytes must be >= 1",
              file=sys.stderr)
        return 2
    if not os.path.isdir(a.input):
        print("reshard error: --input is not a directory", file=sys.stderr)
        return 2
    src = os.path.realpath(a.input)
    files = gather(a.input)
    out = a.output
    if os.path.realpath(out) == src:
        print("reshard error: --output must differ from --input", file=sys.stderr)
        return 2
    if os.path.lexists(out):
        shutil.rmtree(out)
    os.makedirs(out)

    shard_index = 0
    items_in_shard = 0
    rows = []
    for k, (rel, ab) in enumerate(files):
        size = os.path.getsize(ab)
        pieces = max(1, math.ceil(size / b))
        if pieces > n:
            print("reshard error: file %r needs %d pieces > --max-items %d"
                  % (rel, pieces, n), file=sys.stderr)
            return 2
        if items_in_shard + pieces > n:
            shard_index += 1
            items_in_shard = 0
        shard_dir = os.path.join(out, "shard-%03d" % shard_index)
        os.makedirs(shard_dir, exist_ok=True)
        parts_out = []
        with open(ab, 'rb') as fin:
            for p in range(pieces):
                chunk = fin.read(b)
                if pieces == 1:
                    pname = "f_%06d" % k
                else:
                    pname = "f_%06d_%d" % (k, p)
                with open(os.path.join(shard_dir, pname), 'wb') as fout:
                    fout.write(chunk)
                parts_out.append("shard-%03d/%s" % (shard_index, pname))
                items_in_shard += 1
        rows.append("%s\t%s\t%d" % (rel, ",".join(parts_out),
                                    1 if pieces > 1 else 0))

    with open(os.path.join(out, 'manifest.tsv'), 'w', encoding='utf-8') as fh:
        fh.write("\n".join(rows))
        if rows:
            fh.write("\n")
    print("reshard: repacked %d file(s) into %d shard(s)"
          % (len(files), shard_index + 1))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
PYEOF
chmod +x /app/reshard.py

# ---------------- Tool 3: normalize_newlines.py ----------------
cat > /app/normalize_newlines.py <<'PYEOF'
#!/usr/bin/env python3
"""Normalize text files to LF-only line endings, leaving binary bytes intact.

    python3 normalize_newlines.py --src <dir> --dst <dir>
"""
import argparse
import os
import shutil
import sys


def is_binary(path):
    with open(path, 'rb') as fh:
        head = fh.read(4096)
    return b'\x00' in head


def main(argv):
    ap = argparse.ArgumentParser(prog='normalize_newlines.py')
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst', required=True)
    a = ap.parse_args(argv)
    if not os.path.isdir(a.src):
        print("normalize error: --src is not a directory", file=sys.stderr)
        return 2
    os.makedirs(a.dst, exist_ok=True)
    try:
        for root, _dirs, fs in os.walk(a.src):
            rel = os.path.relpath(root, a.src)
            dest_root = a.dst if rel == '.' else os.path.join(a.dst, rel)
            os.makedirs(dest_root, exist_ok=True)
            for f in fs:
                sp = os.path.join(root, f)
                dp = os.path.join(dest_root, f)
                if not os.path.isfile(sp):
                    continue
                if is_binary(sp):
                    shutil.copyfile(sp, dp)
                else:
                    with open(sp, 'rb') as fh:
                        data = fh.read()
                    data = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
                    with open(dp, 'wb') as fh:
                        fh.write(data)
    except (OSError, ValueError) as exc:
        print("normalize error: %s" % exc, file=sys.stderr)
        return 2
    print("normalize: rebuilt %s -> %s" % (a.src, a.dst))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
PYEOF
chmod +x /app/normalize_newlines.py

# ---------------- Run each tool on the shipped fixtures ----------------
python3 /app/mk_leafs.py --listing /app/listing.txt --outdir /app/leaf_tree
python3 /app/reshard.py --input /app/input_tree --output /app/output_tree \
    --max-items 6 --max-bytes 4096
python3 /app/normalize_newlines.py --src /app/mixed_tree --dst /app/clean_tree

echo "Oracle completed: three tools + leaf_tree + output_tree + clean_tree"