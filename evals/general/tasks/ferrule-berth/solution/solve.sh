#!/bin/bash
# Oracle for ferrule-berth: builds the CaDiCaL solver from the pinned clone,
# writes the /app/driver.sh deliverable that drives it, then self-tests the
# driver on every visible fixture shipped in the image.
set -u

# ---- 1. build the solver with the project's own build system ---------------
if [ ! -x /app/cadical ]; then
  (cd /app/src && make -j1) > /tmp/oracle_make.log 2>&1 || {
    echo "oracle: make failed" >&2; tail -20 /tmp/oracle_make.log >&2; exit 1; }
  cp /app/src/build/cadical /app/cadical
  chmod +x /app/cadical
fi

# ---- 2. the driver deliverable ---------------------------------------------
cat > /app/driver.sh <<'DRIVER'
#!/bin/bash
# ferrule-berth driver: drive the CaDiCaL SAT solver built from /app/src.
#   /app/driver.sh <input> <outdir>
# Writes <outdir>/verdict ("s SATISFIABLE" | "s UNSATISFIABLE"), a model for
# satisfiable inputs, and an LRAT proof validated by the solver's own proof
# checker for every unsatisfiable plain DIMACS CNF input.
set -u

input="$1"
outdir="$2"

# ensure the solver binary exists (built by the agent from the pinned source)
if [ ! -x /app/cadical ]; then
  (cd /app/src && make -j1) >/dev/null 2>&1 || { echo "build failed" >&2; exit 1; }
  cp /app/src/build/cadical /app/cadical
  chmod +x /app/cadical
fi

mkdir -p "$outdir"
log="$(mktemp)"

case "$input" in
  *.icnf) kind=incremental ;;
  *) kind=plain ;;
esac

if [ "$kind" = "incremental" ]; then
  /app/cadical -q "$input" > "$log" 2>&1
else
  # plain DIMACS CNF. The solver's own proof checker (--check --checkproof)
  # validates every derived clause as it is emitted; LRAT steps plus the
  # syntactic empty-clause termination make the trail independently auditable.
  /app/cadical --check --lrat --checkproof=2 --no-binary "$input" "$outdir/proof.lrat" > "$log" 2>&1
fi

verdict="$(grep -m1 '^s ' "$log" || true)"
if [ -z "$verdict" ]; then
  echo "no verdict produced" >&2
  exit 1
fi
printf '%s\n' "$verdict" > "$outdir/verdict"

case "$verdict" in
  "s SATISFIABLE")
    grep '^v ' "$log" > "$outdir/model" || true
    ;;
  "s UNSATISFIABLE")
    if [ "$kind" != "incremental" ] && [ ! -s "$outdir/proof.lrat" ]; then
      echo "UNSAT plain input without a proof" >&2
      exit 1
    fi
    ;;
esac
exit 0
DRIVER
chmod +x /app/driver.sh

# ---- 3. self-test the driver on every shipped fixture -----------------------
fail=0
for f in /app/cases/*; do
  out="$(mktemp -d)"
  if ! /app/driver.sh "$f" "$out"; then
    echo "oracle: driver failed on $f" >&2; fail=1; continue
  fi
  grep -qE '^s (SATISFIABLE|UNSATISFIABLE)$' "$out/verdict" || {
    echo "oracle: bad verdict for $f" >&2; fail=1; }
done
[ $fail -eq 0 ] || { echo "oracle: self-test failed" >&2; exit 1; }
echo "oracle: build + driver + self-test ok"
exit 0