#!/bin/bash
# Oracle for halyard-spinnaker: applies the upstream two-file fix to the
# real gohugoio/hugo tree at /app/src (the partial namespace must stop
# rejecting falsy contexts for return-partials, and the predefined return
# wrapper template must execute its body even for falsy arguments, which is
# done upstream by switching the wrapper from a `with .Arg` action to a
# `range (slice .Arg)` action and rewriting the transformer's node surgery
# accordingly), writes /app/repro.sh and /app/summary.md, builds the hugo
# CLI from the fixed tree, and proves the work with the project's own test
# runner: the upstream regression test baked at /opt/golden plus nine of
# the project's own partial/template hugolib tests, all offline. Reads only
# /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/usr/local/go/bin:$PATH
GO=/usr/local/go/bin/go

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || {
    echo "oracle: fix.patch failed to apply" >&2
    exit 1
}
echo "oracle: applied the return-partial falsy-argument fix"

# Build the hugo CLI from the fixed tree.
if ! "$GO" build -o /app/hugo > /tmp/oracle_build.log 2>&1; then
    echo "oracle: go build failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
/app/hugo version | head -1

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the return-partial falsy-argument bug.
# Contract: honour $HUGO_BIN (default /app/hugo), set up a tiny Hugo site
# in a fresh scratch dir under /tmp, run the build with --quiet, print the
# rendered page, exit 0 iff the build succeeded AND the rendered page
# contains the marker string the partial returned.
set -u
HUGO_BIN=${HUGO_BIN:-/app/hugo}
work=$(mktemp -d /tmp/hugo-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/layouts/partials" "$work/content"
printf 'baseURL = "/"\n' > "$work/config.toml"
cat > "$work/layouts/index.html" <<'EOF'
A{{ partial "retval" dict }}B
EOF
printf '{{ return "MARKER-RETVAL" }}\n' > "$work/layouts/partials/retval.html"
printf -- '---\n---\nhello\n' > "$work/content/_index.md"
( cd "$work" && "$HUGO_BIN" --source . --destination public --quiet > build.log 2>&1 )
rc=$?
out=""
if [ -f "$work/public/index.html" ]; then
    out=$(cat "$work/public/index.html")
    echo "$out"
fi
if [ $rc -ne 0 ]; then
    cat "$work/build.log"
    exit 1
fi
echo "$out" | grep -q "MARKER-RETVAL" && exit 0
exit 1
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: when a Hugo template partial that contains a `return` statement is
called with a falsy argument (an empty dictionary `dict`, an empty slice
`slice`, an empty string, `0`, or `false`), the whole site build aborts
with "error calling partial: partial that returns a value needs a non-zero
argument." The partial body is never evaluated, so the value it would have
returned is lost and the page is missing its content. Partials called with
truthy arguments work fine; non-returning partials accept falsy arguments
without complaint.

Cause: two cooperating pieces of the template engine. First, the partial
namespace explicitly rejected a falsy context whenever the partial has a
return value, returning an error instead of rendering. Second, the
predefined wrapper that captures the return value was built on a `with
.Arg` action, whose body only executes when `.Arg` is truthy - so even with
the rejection removed, the partial body inside the wrapper would be skipped
for falsy arguments and the return value lost.

Fix (the minimal change, mirroring upstream): remove the falsy-context
rejection in the partial namespace, and change the predefined return
wrapper from `with .Arg` to `range (slice .Arg)`, whose single iteration
executes its body for any argument value - the transformer code that
rewrites the wrapper before each call was updated to find and splice into
the range node instead of the with node.

Verification: `/app/repro.sh` exits nonzero against the pristine pre-fix
binary at /opt/prefix/hugo and exits 0 with the returned marker rendered
against the rebuilt CLI; the upstream regression test for this bug (planted
from /opt/golden, `TestPartialWithZeroedArgs`, which calls a returning
partial with `dict`, `slice`, `""`, `false` and `0`) passes; nine of the
project's own partial/template hugolib tests still pass; and direct site
builds with falsy arguments arriving from front matter, from a data file,
from a `cond` expression and from another returning partial all render the
expected page.
MD
echo "oracle: wrote /app/summary.md"

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image),
# rebuild the test harness offline and run the targeted subset.
rm -f hugolib/template_test.go
cp /opt/golden/template_test.go hugolib/template_test.go
if ! "$GO" test -vet=off ./hugolib -run TestPartialWithZeroedArgs -v > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q '^--- PASS: TestPartialWithZeroedArgs ' /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}
echo "oracle: golden regression test passes"

if ! "$GO" test -vet=off ./hugolib -run "TestPartialWithReturn|TestPartialCached|TestPartialInline|TestPartialInlineBase|TestTemplateTruth|TestTemplateFuncs|TestTemplateLookupOrder|TestTemplateManyBaseTemplates|TestTemplateNoBasePlease" -v > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: partial/template suite selection did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
for t in TestPartialWithReturn TestPartialCached TestPartialInline TestPartialInlineBase \
         TestTemplateTruth TestTemplateFuncs TestTemplateLookupOrder \
         TestTemplateManyBaseTemplates TestTemplateNoBasePlease; do
    grep -q "^--- PASS: $t " /tmp/oracle_suite.log || {
        echo "oracle: $t did not run and pass" >&2
        exit 1
    }
done
echo "oracle: partial/template suite selection passes"

# Direct reproduction through the deliverable, both directions.
if ! /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    head -10 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
grep -q "MARKER-RETVAL" /tmp/oracle_repro_fixed.out || {
    echo "oracle: repro did not render the returned marker on the fixed tree" >&2
    exit 1
}
if HUGO_BIN=/opt/prefix/hugo /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Leave the tree exactly as the verifier expects: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the two fixed
# source files is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- hugolib/template_test.go || {
    echo "oracle: could not restore hugolib/template_test.go" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, regression suite green, repro OK"
exit 0