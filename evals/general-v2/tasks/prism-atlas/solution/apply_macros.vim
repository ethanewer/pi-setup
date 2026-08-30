" apply_macros.vim — headless prism macro that rewrites depot rows.
"
" A "shapeable" input row has exactly three '|'-separated fields, all non-empty
" and with no surrounding whitespace:
"     <field1>|<field2>|<field3>
" Such a row is rewritten everywhere to:
"     <field2> (<field1>) <field3>
" Any line that is NOT exactly in that shape (empty / whitespace-only lines,
" lines with one '|' or more than two '|', or an empty field) is left
" byte-for-byte unchanged.
"
" Run headless:
"     vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim [file ...]
" With explicit source files those are transformed; with no explicit files, every
" regular file directly below /app/data/rows is transformed. Each transformed
" buffer is saved to /app/transformed/<basename>.
"
set nocompatible
set nomore
silent! call mkdir('/app/transformed', 'p')

if argc() > 0
  let s:files = argv()
else
  let s:files = glob('/app/data/rows/*.txt', 0, 1)
endif

for s:f in s:files
  exe 'edit ' . s:f
  %s/\v^([^|]+)\|([^|]+)\|([^|]+)$/\2 (\1) \3/
  let s:out = '/app/transformed/' . fnamemodify(s:f, ':t')
  exe 'write ' . s:out
  bdelete!
endfor
qa!