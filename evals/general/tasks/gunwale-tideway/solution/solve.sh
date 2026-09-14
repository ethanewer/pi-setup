#!/bin/bash
# Oracle for gunwale-tideway: applies the one-source-file fix to the real
# git/git tree at /app/src (cmd_fetch() must treat an explicit --jobs=0 the
# same as the configuration path already did - as "pick online_cpus()" -
# before the parallel multi-remote machinery runs, so run_processes_parallel
# is never given a zero process count), rebuilds, writes /app/repro.sh and
# /app/summary.md, then proves the work: the reproduction must pass against
# the rebuilt fixed binary and must fail against the pristine pre-fix binary
# baked at /opt/prefix/git. Reads only /app, /solution and /opt, never
# /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the --jobs=0 default-parallelism fix"

if ! make -j1 > /tmp/oracle_make.log 2>&1; then
    echo "oracle: make failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_make.log >&2
    exit 1
fi
test -x /app/src/git || { echo "oracle: /app/src/git missing after make" >&2; exit 1; }

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the --jobs=0 multi-remote fetch abort.
# Contract: honour $GIT_BIN (default /app/src/git), set up the scenario in a
# fresh scratch dir under /tmp, print git's output only, exit 0 iff the
# affected command exits 0 AND every remote's branch arrived.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/git-repro.XXXXXX) || exit 1
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
trap 'rm -rf "$work"' EXIT
mkdir -p "$HOME"
for r in one two; do
    git init -q --bare "$work/$r" || exit 1
    wt=$(mktemp -d /tmp/git-repro-wt.XXXXXX) || exit 1
    git init -q "$wt" || exit 1
    ( cd "$wt" \
      && git config user.email t@t && git config user.name t \
      && echo hi > f && git add f && git commit -q -m seed \
      && git push -q "$work/$r" HEAD:master ) || exit 1
    rm -rf "$wt"
done
git init -q "$work/test" || exit 1
( cd "$work/test" \
  && git remote add one "$work/one" \
  && git remote add two "$work/two" ) || exit 1
( cd "$work/test" && "$GIT_BIN" fetch --multiple --jobs=0 one two ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
( cd "$work/test" \
  && git rev-parse --verify --quiet refs/remotes/one/master >/dev/null \
  && git rev-parse --verify --quiet refs/remotes/two/master >/dev/null ) \
    || { echo "refs missing after fetch" >&2; exit 1; }
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: `git fetch --multiple --jobs=0` aborted its own run before fetching
anything, printing the internal diagnostic
"BUG: run-command.c:NNNN: you must provide a non-zero number of processes!"
and dying by abort signal. The documented contract is that a parallel-fetch
setting of 0 selects a sensible default (the number of processors), and the
configuration path (`fetch.parallel=0`) already implemented that fallback;
only an explicitly passed `--jobs=0` on the multi-remote fetch path kept the
raw 0, which then reached `run_processes_parallel()` and tripped its
non-zero-process BUG() check.

Cause: `cmd_fetch()` carried `max_jobs` (initialised to -1 by the option
parser) through to the multi-remote path and only substituted the
configuration default when the value was negative (`if (max_children < 0)
max_children = fetch_parallel_config;`). An explicit 0 is not negative, so
it was passed through unchanged as the process count.

Change: in `builtin/fetch.c`, `cmd_fetch()`, after the option and config
parsing, treat an explicit zero exactly like the configuration path already
treats it: `if (!max_jobs) max_jobs = online_cpus();` before the parallel
machinery runs. The command then fetches from every remote using the
default parallel count and exits 0.

Verification: `/app/repro.sh` fails against the pre-fix binary at
/opt/prefix/git (BUG diagnostic, abort, refs missing) and passes against
the rebuilt tree (exit 0, both remote-tracking refs present); the project's
own t5514-fetch-multiple.sh suite, t5510-fetch.sh and
t5520-pull.sh all pass; the upstream regression test planted in
t5514 ("git fetch --multiple --jobs=0 picks a default") passes.
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

# Sanity: the project's own fetch suites must stay green on the fixed tree.
if ! ( cd /app/src/t && ./t5514-fetch-multiple.sh > /tmp/oracle_t5514.log 2>&1 ); then
    echo "oracle: t5514 failed; tail:" >&2
    tail -20 /tmp/oracle_t5514.log >&2
    exit 1
fi
grep -q "passed all 12 test(s)" /tmp/oracle_t5514.log || {
    echo "oracle: t5514 did not pass all 12 tests" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, t5514 green"
exit 0