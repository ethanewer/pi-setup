#!/bin/bash
# Oracle for hinge-lathe. Writes the deliverable macro script (the real work:
# a headless vim pass implementing the documented row transform), then RUNS it
# on the shipped corpora to produce /app/outbox/batch-*.txt. Never reads /tests.
set -eu

SCRIPT="/app/bulletin.vim"

cat > "$SCRIPT" <<'VIM'
" hinge-lathe deliverable: headless relay-bulletin macro pass.
"
" Usage: vim -es -N -u NONE -i NONE -n -S /app/bulletin.vim [file...]
"   - no file args: transform every /appdata/relay/*.txt
"   - file args: transform exactly those files
" Results are written to /app/outbox/<basename>.
"
" Row dialects (shapeable):
"   TKT-<digits>|<LOC>|<STATUS>  ->  <LOC> [TKT-<digits>] <STATUS>
"   load=<num>|<word>            ->  load <word> <sign><int>.<frac-3digits>
" Every other line is passed through byte-for-byte.

call mkdir('/app/outbox', 'p')

if argc() > 0
  let s:files = []
  for s:i in range(argc())
    call add(s:files, argv(s:i))
  endfor
else
  let s:files = sort(split(globpath('/appdata/relay', '*.txt'), "\n"))
endif

for s:f in s:files
  execute 'edit! ' . fnameescape(s:f)

  " ticket rows
  silent! %s/^TKT-\(\d\+\)|\([A-Z]\+\( [A-Z]\+\)*\)|\([A-Z]\+\)$/\=submatch(2) . ' [TKT-' . submatch(1) . '] ' . submatch(4)/

  " metric rows (fraction right-padded to exactly 3 digits)
  silent! %s/^load=\(-\)\?\(\d\+\)\.\(\d\{1,3\}\)|\([a-z]\+\)$/\=printf('load %s %s%s.%s', submatch(4), submatch(1) ==# '-' ? '-' : '+', submatch(2), submatch(3) . repeat('0', 3 - strlen(submatch(3))))/

  execute 'write! ' . fnameescape('/app/outbox/' . fnamemodify(s:f, ':t'))
  bwipeout!
endfor

qall!
VIM

chmod +x "$SCRIPT"

# Run the macro pass on the shipped corpora (no file args -> default scan).
vim -es -N -u NONE -i NONE -n -S "$SCRIPT"

echo "solve.sh done -> $SCRIPT and /app/outbox/"
ls -l /app/outbox/batch-1.txt /app/outbox/batch-2.txt /app/outbox/batch-3.txt
