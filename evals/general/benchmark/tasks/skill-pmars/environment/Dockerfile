FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

# pMARS (portable Core War simulator / MARS assembler), built from vendored source
COPY files/pmars-src /app/pmars-src
RUN cd /app/pmars-src && gcc -O2 -DSERVER -DEXT94 -DPERMUTATE \
    -o /app/pmars pmars.c asm.c eval.c disasm.c cdb.c sim.c pos.c clparse.c global.c token.c str_eng.c \
 && rm -rf /app/pmars-src

COPY files/warrior.red /app/warrior.red