#!/bin/bash
# Verifier for the nectar-helix task.
#
# executes-deliverable. /app/mk_leafs.py, /app/reshard.py and
# /app/normalize_newlines.py must exist and behave per contract:
#   - mk_leafs creates zero-byte files for every file entry (dirs for '/'
#     entries) and rejects absolute / '..' / colliding listings.
#   - reshard repacks a source tree so every directory holds <= max-items
#     entries and no file exceeds max-bytes (splitting oversized files), with a
#     reassemblable manifest.tsv.
#   - normalize_newlines makes text files LF-only (no 0x0D) and copies binary
#     (NUL-containing) files byte-identically.
# The verifier independently recomputes all expectations (not oracle-coupled).
set -u
mkdir -p /logs/verifier
reward=0
ok=1

if [ ! -f /app/mk_leafs.py ] || [ ! -f /app/reshard.py ] || \
   [ ! -f /app/normalize_newlines.py ] || [ ! -d /app/output_tree ]; then
    echo "missing a deliverable (/app/mk_leafs.py, /app/reshard.py, /app/normalize_newlines.py, /app/output_tree)" >&2
    ok=0
fi

# ---------- embedded, contract-independent checkers ----------
cat > /tmp/nhck.py <<'PYEOF'
import os, sys

def leafs_parse(listing):
    entries = []
    for line in open(listing, 'r', encoding='utf-8', errors='surrogateescape').read().splitlines():
        s = line.strip()
        if not s or s[0] == '#':
            continue
        is_dir = s.endswith('/')
        body = s[:-1] if is_dir else s
        if body:
            entries.append((body, is_dir))
    return entries

def leafs_ok(listing, outdir):
    try:
        entries = leafs_parse(listing)
    except OSError:
        return False, "listing unreadable"
    for body, is_dir in entries:
        t = os.path.join(outdir, body)
        if is_dir:
            if not os.path.isdir(t):
                return False, "missing dir %r" % body
        else:
            if not os.path.isfile(t):
                return False, "missing file %r" % body
            if os.path.getsize(t) != 0:
                return False, "file %r not zero bytes" % body
    return True, "ok"

def _norm_bin(sp):
    with open(sp, 'rb') as fh:
        return b'\x00' in fh.read(4096)

def normalize_ok(src, dst):
    src_files, dst_files = [], []
    for root, _, fs in os.walk(src):
        for f in fs:
            p = os.path.join(root, f)
            if os.path.isfile(p):
                src_files.append(os.path.relpath(p, src))
    for root, _, fs in os.walk(dst):
        for f in fs:
            p = os.path.join(root, f)
            if os.path.isfile(p):
                dst_files.append(os.path.relpath(p, dst))
    if set(src_files) != set(dst_files):
        return False, "file set mismatch"
    for rel in src_files:
        sp = os.path.join(src, rel)
        dp = os.path.join(dst, rel)
        if not os.path.isfile(dp):
            return False, "missing output %r" % rel
        s = open(sp, 'rb').read()
        if _norm_bin(sp):
            if open(dp, 'rb').read() != s:
                return False, "binary not byte-identical %r" % rel
        else:
            d = open(dp, 'rb').read()
            if b'\r' in d:
                return False, "text has CR in %r" % rel
            want = s.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
            if d != want:
                return False, "text not LF normalized %r" % rel
    return True, "ok"

def reshard_ok(src, out, n, b):
    n, b = int(n), int(b)
    if not os.path.isdir(out):
        return False, "output missing"
    # per-directory item cap
    for dp, dirs, fs in os.walk(out):
        if len(dirs) + len(fs) > n:
            return False, "dir %r exceeds %d items" % (dp, n)
    # per-file byte cap (ignore symlink artifacts)
    for dp, _, fs in os.walk(out):
        for f in fs:
            p = os.path.join(dp, f)
            if os.path.isfile(p) and os.path.getsize(p) > b:
                return False, "file %r > %d bytes" % (p, b)
    man = os.path.join(out, 'manifest.tsv')
    if not os.path.isfile(man):
        return False, "manifest missing"
    src_files = []
    for root, _, fs in os.walk(src):
        for f in fs:
            p = os.path.join(root, f)
            if os.path.isfile(p):
                src_files.append(os.path.relpath(p, src))
    manifest = {}
    for line in open(man, 'r', encoding='utf-8').read().splitlines():
        parts = line.split('\t')
        if len(parts) != 3:
            return False, "bad manifest row"
        manifest[parts[0]] = parts[1].split(',')
    if set(src_files) != set(manifest.keys()):
        return False, "manifest/source file set mismatch"
    for rel, outparts in manifest.items():
        assembled = b''.join(
            open(os.path.join(out, op), 'rb').read() for op in outparts)
        if assembled != open(os.path.join(src, rel), 'rb').read():
            return False, "reassembly mismatch for %r" % rel
    return True, "ok"

def main():
    cmd = sys.argv[1]
    if cmd == 'leafs_ok':
        ok, msg = leafs_ok(sys.argv[2], sys.argv[3])
    elif cmd == 'normalize_ok':
        ok, msg = normalize_ok(sys.argv[2], sys.argv[3])
    elif cmd == 'reshard_ok':
        ok, msg = reshard_ok(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        print("unknown cmd", cmd); sys.exit(2)
    print(msg)
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
PYEOF

run_check() { # run_check <args...> ; returns 0 on success
    local m
    if m=$(python3 /tmp/nhck.py "$@"); then
        return 0
    else
        echo "check failed: $* -> $m" >&2
        return 1
    fi
}

tmp() { mktemp -d; }

if [ "$ok" = 1 ]; then
    # ---- VISIBLE: re-run each tool on the shipped fixtures into fresh dirs ----
    V1=$(tmp); V2=$(tmp); V3=$(tmp)
    if python3 /app/mk_leafs.py --listing /app/listing.txt --outdir "$V1"; then
        run_check leafs_ok /app/listing.txt "$V1" || ok=0
    else
        echo "visible mk_leafs failed" >&2; ok=0
    fi
    if python3 /app/reshard.py --input /app/input_tree --output "$V2" \
            --max-items 6 --max-bytes 4096 >/tmp/rs.log 2>&1; then
        run_check reshard_ok /app/input_tree "$V2" 6 4096 || ok=0
    else
        echo "visible reshard failed: $(tail -1 /tmp/rs.log)" >&2; ok=0
    fi
    if python3 /app/normalize_newlines.py --src /app/mixed_tree --dst "$V3" >/dev/null 2>&1; then
        run_check normalize_ok /app/mixed_tree "$V3" || ok=0
    else
        echo "visible normalize failed" >&2; ok=0
    fi
    rm -rf "$V1" "$V2" "$V3"

    # the produced deliverable /app/output_tree must itself verify
    run_check reshard_ok /app/input_tree /app/output_tree 6 4096 || ok=0
fi

# ---- HIDDEN: mk_leafs valid ----
if [ "$ok" = 1 ]; then
    for d in /tests/hidden/case_mk_1; do
        [ -f "$d/listing.txt" ] || continue
        v=$(tmp)
        if python3 /app/mk_leafs.py --listing "$d/listing.txt" --outdir "$v" >/dev/null 2>&1; then
            run_check leafs_ok "$d/listing.txt" "$v" || ok=0
        else
            echo "hidden mk_leafs case_mk_1 rejected valid listing" >&2; ok=0
        fi
        rm -rf "$v"
    done
fi

# ---- HIDDEN: mk_leafs must reject malformed (case_mk_2, case_mk_3) ----
if [ "$ok" = 1 ]; then
    for d in /tests/hidden/case_mk_2 /tests/hidden/case_mk_3; do
        v=$(tmp)
        if python3 /app/mk_leafs.py --listing "$d/listing.txt" --outdir "$v" >/tmp/ml.log 2>&1; then
            echo "hidden mk_leafs accepted malformed listing $d" >&2; ok=0
        fi
        rm -rf "$v"
    done
    # empty listing must succeed with empty/partial outdir
    e=$(tmp)
    printf '' > "$e/empty.lst"
    if ! python3 /app/mk_leafs.py --listing "$e/empty.lst" --outdir "$e/out" >/dev/null 2>&1; then
        echo "mk_leafs failed on empty listing" >&2; ok=0
    fi
    rm -rf "$e"
fi

# ---- HIDDEN: reshard ----
if [ "$ok" = 1 ]; then
    run_rs() { # run_rs <sourcedir> <n> <b>
        local src="$1" n="$2" b="$3" ov
        ov=$(tmp)
        if ! python3 /app/reshard.py --input "$src" --output "$ov" \
                --max-items "$n" --max-bytes "$b" >/tmp/rs.log 2>&1; then
            echo "reshard failed on $src: $(tail -1 /tmp/rs.log)" >&2
            rm -rf "$ov"; return 1
        fi
        if ! run_check reshard_ok "$src" "$ov" "$n" "$b"; then
            echo "reshard property failure on $src" >&2
            rm -rf "$ov"; return 1
        fi
        rm -rf "$ov"
    }
    run_rs /tests/hidden/case_rs_1/src 5 100000 || ok=0
    run_rs /tests/hidden/case_rs_2/src 4 2000 || ok=0
    run_rs /tests/hidden/case_rs_3/src 4 10000 || ok=0
fi

# ---- HIDDEN: normalize ----
if [ "$ok" = 1 ]; then
    run_nl() { # src dir
        local src="$1" o
        o=$(tmp)
        if ! python3 /app/normalize_newlines.py --src "$src" --dst "$o" >/dev/null 2>&1; then
            echo "normalize failed on $src" >&2
            rm -rf "$o"; return 1
        fi
        if ! run_check normalize_ok "$src" "$o"; then
            echo "normalize property failure on $src" >&2
            rm -rf "$o"; return 1
        fi
        rm -rf "$o"
    }
    run_nl /tests/hidden/case_nl_1/src || ok=0
    run_nl /tests/hidden/case_nl_2/src || ok=0
    run_nl /tests/hidden/case_nl_3/src || ok=0
    run_nl /tests/hidden/case_nl_4/src || ok=0
fi

[ "$ok" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0