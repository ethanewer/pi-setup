#!/bin/bash
# Real oracle for teal-macro: record a compact macro register set, apply it to
# the visible fixtures to produce /app/transformed.txt, and sanity-check the
# budget the same way the grader does. Never reads /tests.
set -eu

BUDGET=40

cat > /app/macros.vim <<'EOF'
" teal-macro primary macro: rewrite WORD,NUMBER,WORD -> WORD3 WORD1 (NUMBER)
" one :s with very-magic pattern; executed once per line via :g/^/normal @a
let @a=":s/\\v(\\w+),(\\d+),(\\w+)/\\3 \\1 (\\2)/\r"
EOF

# Apply the macro with the exact mechanism the grader uses, on the visible
# fixtures, to produce the deliverable.
cat > /tmp/teal_solve.vim <<'EOF'
set nocompatible nomore
edit /app/source.txt
source /app/macros.vim
%g/^/normal @a
call writefile(getline(1, '$'), '/app/transformed.txt')
qa!
EOF

vim -Nu NONE -n -i NONE --not-a-term -es -S /tmp/teal_solve.vim

# Budget self-check (mirror of the grader's measurement).
cat > /tmp/teal_budget.vim <<'EOF'
source /app/macros.vim
let s:total = 0
for s:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
  let s:total += len(getreg(s:c))
endfor
call writefile([string(s:total)], '/tmp/teal_oracle_budget.txt')
qa!
EOF
vim -Nu NONE -n -i NONE --not-a-term -es -S /tmp/teal_budget.vim
TOTAL=$(cat /tmp/teal_oracle_budget.txt)
echo "oracle macro budget used: $TOTAL (ceiling $BUDGET)"
if [ "$TOTAL" -gt "$BUDGET" ]; then
  echo "oracle exceeds budget" >&2
  exit 1
fi

cmp /app/transformed.txt /app/wanted.txt

echo "solve.sh done"
ls -l /app/macros.vim /app/transformed.txt
