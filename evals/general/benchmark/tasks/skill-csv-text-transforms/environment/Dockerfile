FROM bench-base:python-3.12

WORKDIR /app

# CSV with messy text fields: surrounding whitespace, inconsistent case,
# and run-on whitespace inside status values.
RUN cat > /app/records.csv <<'EOF'
id,user,status
  1,  Ada ,       Lead    Engineer
  2,  Alice ,    Beta    Tester
  3,  Linus ,   Kernel    Hacker
EOF