FROM bench-base:python-3.12

WORKDIR /app

# Each line: <value> <from_base> <to_base>. Rewriting natural numbers between bases.
RUN cat > /app/numbers.txt <<'EOF'
5 10 2
1010 2 10
255 10 16
EOF