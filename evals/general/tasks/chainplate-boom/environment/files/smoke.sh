#!/bin/bash
# Build-time smoke for chainplate-boom: proves the image ships the BUGGY
# state at the pinned parent commit, so the "bug present" direction of the
# acceptance gate is real. Fails the image build if the parent's
# chomsky_normal_form does NOT crash on the issue's inputs, or if the
# upstream regression tests somehow pass against the buggy tree.
set -u
cd /app/src

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

# 1. Reproduce the reported symptom: a punctuation terminal among siblings
#    must raise AttributeError at the parent commit.
out=$(python3 -c "
from nltk.tree import Tree
from nltk.tree.transforms import chomsky_normal_form
chomsky_normal_form(Tree.fromstring('(S (S 1) + (S 2))'), factor='right')
" 2>&1) && fail "repro with terminal '+' did not raise"
echo "$out" | grep -q "AttributeError" || fail "repro with terminal '+' raised without AttributeError: $(echo "$out" | tail -2)"

# 2. Same path with a NON-STRING terminal (integer): must also crash.
out=$(python3 -c "
from nltk.tree import Tree
from nltk.tree.transforms import chomsky_normal_form
chomsky_normal_form(Tree('S', [Tree('A',['a']), 7, Tree('B',['b']), Tree('C',['c'])]), factor='right')
" 2>&1) && fail "repro with int terminal did not raise"
echo "$out" | grep -q "AttributeError" || fail "repro with int terminal raised without AttributeError: $(echo "$out" | tail -2)"

# 3. The upstream regression test file (from the fix commit) must FAIL against
#    the parent's code, with exactly the two new tests failing on
#    AttributeError.  If the pinned dependency versions do not reproduce the
#    bug, this layer fails and the image is never built.
if python3 -m pytest /opt/golden/test_treetransforms.py -q -p no:cacheprovider > /tmp/smoke_golden.log 2>&1; then
  fail "golden upstream regression tests PASS at the parent commit (bug absent)"
fi
grep -q "test_chomsky_normal_form_with_terminal_siblings" /tmp/smoke_golden.log \
  || fail "golden log missing terminal_siblings failure"
grep -q "test_chomsky_normal_form_with_nonstring_terminal" /tmp/smoke_golden.log \
  || fail "golden log missing nonstring_terminal failure"
grep -q "AttributeError" /tmp/smoke_golden.log || fail "no AttributeError in golden log"

# 4. The tree's own pre-existing transform tests and doctests are green at
#    the parent (the baseline the verifier re-checks after the fix).
python3 -m pytest nltk/test/unit/test_treetransforms.py -q -p no:cacheprovider > /tmp/smoke_own.log 2>&1 \
  || fail "the tree's own unit tests fail at parent: $(tail -3 /tmp/smoke_own.log)"
python3 -m doctest nltk/test/treetransforms.doctest > /tmp/smoke_doctest.log 2>&1 \
  || fail "tree transforms doctest fails at parent: $(tail -3 /tmp/smoke_doctest.log)"

echo "smoke checks passed: bug reproduces (str and int terminals), golden regression tests fail, own suite green"