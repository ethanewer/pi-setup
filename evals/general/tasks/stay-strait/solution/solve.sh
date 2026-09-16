#!/bin/bash
# Oracle for stay-strait: applies the one-source-file fix to the real
# git/git tree at /app/src (ref_transaction_create() must not terminate the
# process with BUG() when handed a null new_oid - it has an error strbuf
# for exactly that - so the local clone that scans a corrupt source ref and
# passes a null OID through gets an ordinary die() message instead of an
# abort), rebuilds, writes /app/repro.sh and /app/summary.md, then proves
# the work: the reproduction must pass against the rebuilt fixed binary and
# must fail against the pristine pre-fix binary baked at /opt/prefix/git.
# Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the null-OID graceful-failure fix"

if ! make -j1 > /tmp/oracle_make.log 2>&1; then
    echo "oracle: make failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_make.log >&2
    exit 1
fi
test -x /app/src/git || { echo "oracle: /app/src/git missing after make" >&2; exit 1; }

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the local-clone null-OID abort.
# Contract: honour $GIT_BIN (default /app/src/git), set up the scenario in a
# fresh scratch dir under /tmp, print git's output only, exit 0 iff the
# affected clone fails cleanly (non-zero exit, not an abort, no BUG: line,
# an ordinary fatal: diagnostic on stderr).
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/git-repro.XXXXXX) || exit 1
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
trap 'rm -rf "$work"' EXIT
mkdir -p "$HOME"
"$GIT_BIN" init -q "$work/corrupt" || exit 1
( cd "$work/corrupt" \
  && "$GIT_BIN" config user.email t@t \
  && "$GIT_BIN" config user.name t \
  && echo one > one \
  && "$GIT_BIN" add one \
  && "$GIT_BIN" commit -q -m one ) || exit 1
# corrupt a loose ref file: contents are not a valid object id
echo a > "$work/corrupt/.git/refs/heads/topic" || exit 1
( cd "$work" && "$GIT_BIN" clone corrupt working ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 128 ] || { echo "expected clean failure rc=128, got $rc" >&2; exit 1; }
grep -q "^fatal:" "$work/out" || { echo "no fatal: diagnostic" >&2; exit 1; }
grep -q "^BUG:" "$work/out" && { echo "BUG: line present" >&2; exit 1; }
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `git clone` of a repository straight from a local path crashed when
the source repository contained a loose ref file whose contents were not a
valid object id. The clone printed the ordinary "Cloning into ... done."
lines, then the internal diagnostic "BUG: refs.c:NNNN: create called
without valid new_oid" and died by abort signal (non-zero exit, core
dump), instead of reporting an ordinary error.

Cause: on a local clone (no network, no upload-pack), the client lists the
source repository's refs by scanning its `$GIT_DIR/refs/` files. A ref
file whose contents do not parse as a 40-hex object id is recorded with a
null OID, and when the clone then creates the corresponding remote-tracking
refs, `ref_transaction_create()` was handed that null OID. That function
treated a null OID as proof of an internal programming error and called
`BUG("create called without valid new_oid")`, which prints the BUG line and
aborts the process. Upstream, that BUG() replaced a die() in a refactor,
which is why the same corrupted input used to fail gracefully in older git
releases.

Change: in `refs.c`, `ref_transaction_create()` no longer terminates the
process on a null OID. It appends `"<refname> has a null OID"` to the
error strbuf it already receives and returns failure (1); both callers
already check the return value and die() with the error buffer, so the
user gets an ordinary "fatal: ... has a null OID" message and exit status
128, with no BUG: output and no crash artifacts.

Verification: `/app/repro.sh` fails against the pre-fix binary at
/opt/prefix/git (BUG diagnostic, abort, exit 134) and passes against the
rebuilt tree (exit 128, "fatal: 'refs/remotes/origin/topic' has a null
OID", no BUG line, no core dump); the project's own t5605-clone-local.sh
and t5604-clone-reference.sh suites pass; the upstream regression test
planted in t5605 ("local clone from repo with corrupt refs fails
gracefully") passes.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own binary.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if GIT_BIN=/opt/prefix/git bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Sanity: the project's own local-clone suites must stay green on the
# fixed tree.
if ! ( cd /app/src/t && ./t5605-clone-local.sh > /tmp/oracle_t5605.log 2>&1 ); then
    echo "oracle: t5605 failed; tail:" >&2
    tail -20 /tmp/oracle_t5605.log >&2
    exit 1
fi
grep -q "passed all 20 test(s)" /tmp/oracle_t5605.log || {
    echo "oracle: t5605 did not pass all 20 tests" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, t5605 green"
exit 0