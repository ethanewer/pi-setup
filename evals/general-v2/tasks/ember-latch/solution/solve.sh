#!/bin/bash
# Oracle for tasks/ember-latch (executes-deliverable).
#
# Lays down the macro script at /app/apply_macros.vim, then RUNS it headlessly
# over the shipped feeds so /app/normalized/feed-north.txt, feed-south.txt,
# feed-east.txt and feed-west.txt are computed, not canned. Never reads /tests.
set -eu

cat > /app/apply_macros.vim <<'VIM'
" apply_macros.vim — headless ember-latch macro that normalizes telemetry rows.
"
" A "shapeable" row is a single line matching EXACTLY:
"     <level>|<date>|<message>
"   <level>   : one or more lowercase ASCII letters [a-z]+
"   <date>    : zero-padded \d{4}-\d{2}-\d{2} (pattern only, no calendar math)
"   <message> : one or more characters containing no '|'
" Every shapeable row is rewritten to:
"     <date> [<LEVEL>] <message>
" with <LEVEL> the uppercased level. Any line not exactly in that shape
" (blank lines, wrong field counts, uppercase level, non-zero-padded date,
" empty message, '|' inside the message, surrounding whitespace) is left
" byte-for-byte unchanged.
"
" Run headless:
"     vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim [file ...]
" With explicit source files exactly those are transformed; with no explicit
" files, every *.txt directly below /app/data/feeds is transformed. Each
" transformed buffer is saved to /app/normalized/<basename>.

set nocompatible
set nomore
silent! call mkdir('/app/normalized', 'p')

if argc() > 0
  let s:files = argv()
else
  let s:files = glob('/app/data/feeds/*.txt', 0, 1)
endif

for s:f in s:files
  exe 'edit ' . s:f
  " Row macro: match the exact shape, then rebuild the line with the date
  " first, the uppercased level in brackets, and the untouched message.
  %s/\v^([a-z]+)\|(\d{4}-\d{2}-\d{2})\|([^|]+)$/\=submatch(2) . ' [' . toupper(submatch(1)) . '] ' . submatch(3)/
  let s:out = '/app/normalized/' . fnamemodify(s:f, ':t')
  exe 'write ' . s:out
  bdelete!
endfor
qa!
VIM

chmod +x /app/apply_macros.vim

# Run the macro script over the shipped feeds to produce the deliverables.
vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim \
    /app/data/feeds/feed-north.txt /app/data/feeds/feed-south.txt \
    /app/data/feeds/feed-east.txt /app/data/feeds/feed-west.txt </dev/null

# Guard: every declared deliverable output exists after the transform pass.
for f in /app/normalized/feed-north.txt /app/normalized/feed-south.txt \
         /app/normalized/feed-east.txt /app/normalized/feed-west.txt; do
    [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

echo "solve.sh finished:"
ls -la /app/apply_macros.vim /app/normalized/
