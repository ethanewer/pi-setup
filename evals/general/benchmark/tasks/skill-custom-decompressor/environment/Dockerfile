FROM bench-base:python-3.12

WORKDIR /app

# A file produced by a fictional custom compressor. Each line is:
#   <count> <two-hex-digit byte>
# meaning "emit <byte value> <count> times". Concatenate every line's run in
# file order to recover the original byte stream.
RUN cat > /app/packed.dat <<'EOF'
1 68
1 65
2 6c
1 6f
1 20
1 62
1 75
1 69
1 6c
1 64
1 20
1 68
1 61
1 63
1 6b
1 61
1 74
1 68
1 6f
1 6e
EOF