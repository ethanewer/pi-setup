FROM bench-base:python-3.12

WORKDIR /app

# A list of raw 32-bit MIPS instruction words, one per line.
RUN cat > /app/instructions.txt <<'EOF'
0x00000020
0x8e0a000c
0x22510008
EOF