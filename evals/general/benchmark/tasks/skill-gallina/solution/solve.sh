#!/bin/bash
set -euo pipefail

cat > /app/gallina.v <<'EOF'
Fixpoint double (n : nat) : nat :=
  match n with
  | 0 => 0
  | S k => S (S (double k))
  end.
EOF