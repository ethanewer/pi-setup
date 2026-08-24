FROM bench-base:node-22

WORKDIR /app

COPY files/ /app/_build/
RUN python3 /app/_build/build_elf_big.py /app/prog.elf
RUN rm -rf /app/_build