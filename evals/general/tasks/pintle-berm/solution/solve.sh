#!/bin/bash
# Oracle for pintle-berm: applies the upstream fix to the rust-lang/regex
# checkout at /app/src (trip-wire in regex-automata/src/meta/limited.rs that
# makes the reverse search surrender to the slower correct path when it
# cannot prove its match is the leftmost one), appends an authored
# regression case to testdata/regression.toml, then rebuilds and proves the
# project's own harness passes.
set -e

python3 /solution/fix.py /app/src

cat > /app/report.md <<'EOF'
The bug: for optional-prefix patterns the reverse inner optimization in
regex-automata/src/meta/limited.rs could stop at a real but non-leftmost
match. I added regression case oracle-reverse-inner-repro to
testdata/regression.toml expecting the leftmost 0..9 match with groups
[0..3],[4..6],[7..9]; the harness failed before the fix. The fix records
whether the DFA was dead prior to the end-of-input transition and, when the
reverse search reaches the start of its span with a found match starting
later than that start while the FSM could keep matching, abandons the
optimization with a retry error so the correct leftmost match is found.
EOF

echo "== rebuilt harness, running the project's own suite =="
cd /app/src
export PATH=/opt/cargo/bin:$PATH CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup
cargo test --test integration --no-run > /tmp/oracle-build.log 2>&1
cargo test --test integration -- suite_string::default
echo "oracle: repaired tree passes suite_string::default"