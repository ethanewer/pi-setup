set nocompatible nomore
" headless driver for teal-macro. Environment variables:
"   TSRC  - source file to edit   (default /app/source.txt)
"   TOUT  - where to write the transformed buffer (default /tmp/teal_out.txt)
"   TFLAG - where to record whether sourcing modified the buffer
"   TBUD  - where to record the measured keystroke budget
if empty($TSRC) | let $TSRC = '/app/source.txt' | endif
if empty($TOUT) | let $TOUT = '/tmp/teal_out.txt' | endif
if empty($TFLAG) | let $TFLAG = '/tmp/teal_flag.txt' | endif
if empty($TBUD) | let $TBUD = '/tmp/teal_budget.txt' | endif
execute 'edit' $TSRC
source /app/macros.vim
if &modified
  call writefile(['MODIFIED'], $TFLAG)
else
  call writefile(['CLEAN'], $TFLAG)
endif
let s:total = 0
for s:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
  let s:total += len(getreg(s:c))
endfor
call writefile([string(s:total), string(len(getreg('a')))], $TBUD)
%g/^/normal @a
call writefile(getline(1, '$'), $TOUT)
qa!
