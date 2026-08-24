#!/bin/bash
# Oracle solution for item-005-hard.
set -euo pipefail

# 1. Build pMARS (no-display SERVER variant) and install at /app/pmars.
cd /app/pmars-src/src
# The source snapshot ships stale Mach-O object files; remove them first.
rm -f ./*.o
make -f Makefile all >/tmp/pmars_build.log 2>&1 || { cat /tmp/pmars_build.log; exit 1; }
cp pmars /app/pmars
chmod +x /app/pmars

# 2. Use a generalist killer: a stone/imp-spiral "Aeka"-style warrior that
#    beats or draws against scanners, stones, papers and imp spirals alike.
cat > /app/tournament/mine.red <<'EOF'
;redcode-94
;name     Aeka
;kill     Aeka
;author   T.Hsu
;strategy Suicidal stone & vector launched, gate busting imp spiral
;assert   CORESIZE == 8000 && MAXLENGTH >= 100
;  1.0 Origin based on Cannonade by P.Kline

imp_sz01    equ     2668
imp_sz02    equ     imp_sz01
imp_sz03    equ     2667
imp_prc01   equ     8
imp_prc02   equ     imp_prc01
imp_prc03   equ     10
imp_off01   equ     -2
imp_off02   equ     0
imp_off03   equ     -7
imp_first   equ     (start-1834)+2*imp_sz02
stone_inc   equ     190
stone_offst equ     701
dec_offst   equ     (imp_sz03*2)-stone_inc

            org     start
;  Boot strap
start       mov.i   imp_2,imp_first+imp_off02+2
            mov.i   imp_3,imp_first+imp_off03
            mov.i   <stone_src,@stone_dst2
            mov.i   <stone_src,<stone_dst
            mov.i   <stone_src,<stone_dst
            mov.i   <stone_src,<stone_dst
            spl     @stone_dst,<dec_offst
            mov.i   <stone_src,<stone_dst
;  Vector launch the imps
imp_split   spl     1,<dec_offst
            spl     1,<dec_offst
            mov.i   imp_2,<start
stone_dst   mov.i   -2,#stone_end+1-stone_offst
stone_dst2  mov.i   -1,#stone_end+1-(stone_offst-1)
            spl     <0,#imp_vector
stone_src   djn.a   @(imp_vector-1),#stone_end+1
;  Self splitting stone and core clear
stone       mov.i   <stone_spl+5+stone_inc*800,stone_spl
stone_spl   spl     stone,<dec_offst+stone
            add.f   stone_end+1,stone
            djn.f   stone_spl,<dec_offst+stone
stone_end   mov.i   stone_inc,<-stone_inc
;  Decoy
cnt         for     65
            dat     0,0
            rof
;  Launch vectors
imp_2       mov.i   #(imp_sz02/2),imp_sz02
imp_3       mov.i   #(imp_sz03/2),imp_sz03

imp_A_fld   equ     imp_first+(imp_prc&who+1-2*cnt)*imp_sz&who+imp_off&who
imp_B_fld   equ     imp_first+(imp_prc&who+0-2*cnt)*imp_sz&who+imp_off&who
who         for     3
cnt         for     (imp_prc&who)/2
            jmp     imp_A_fld,imp_B_fld
            rof
            rof
imp_vector
            end
EOF

# 3. Confirm visible-opponent score.
cd /app/tournament
./benchmark.sh mine.red
exit 0