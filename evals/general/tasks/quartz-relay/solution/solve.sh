#!/bin/bash
# Oracle for quartz-relay: writes the headless vim script /app/apply_relabel.vim
# (the actual work) and RUNS it headless over the shipped feed fixtures to
# produce /app/transformed/*. Never reads /tests.
set -eu

SCRIPT="/app/apply_relabel.vim"

cat > "$SCRIPT" <<'VIM'
" apply_relabel.vim - headless relabel pass for Quartz Relay telemetry feeds.
"
" A shapeable row matches ^(\d{4})-(\d{2})-(\d{2});([A-Z]{3});([^;]+)$ and is
" rewritten to:
"     <LABEL> [<CODE>] <DD>.<MM>.<YYYY>
" Any row not in exactly that shape is left byte-for-byte unchanged.
"
" Headless:
"   vim -es -N -u NONE -i NONE -n -S /app/apply_relabel.vim [file ...]
" No args: relabel every *.txt directly under /app/data/feeds/. With args:
" relabel exactly those files. Results go to /app/transformed/<basename>.
set nocompatible
set nomore
silent! call mkdir('/app/transformed', 'p')

if argc() > 0
  let s:files = argv()
else
  let s:files = glob('/app/data/feeds/*.txt', 0, 1)
endif

for s:f in s:files
  exe 'edit ' . s:f
  %s/\v^(\d{4})-(\d{2})-(\d{2});([A-Z]{3});([^;]+)$/\5 [\4] \3.\2.\1/
  exe 'write! ' . '/app/transformed/' . fnamemodify(s:f, ':t')
  bdelete!
endfor

qa!
VIM

# Run the script headless over the shipped fixtures to produce the
# transformed deliverables.
cd /app
vim -es -N -u NONE -i NONE -n -S "$SCRIPT" </dev/null

echo "solve.sh done -> $SCRIPT and /app/transformed/*.txt (station-a..d)"
ls -l /app/apply_relabel.vim /app/transformed/*.txt
