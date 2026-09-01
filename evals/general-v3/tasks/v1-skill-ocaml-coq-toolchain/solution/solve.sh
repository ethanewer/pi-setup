#!/bin/bash
# Oracle solution for skill-ocaml-coq-toolchain.
set -euo pipefail

cat > /app/my_probe.v <<'EOF'
Lemma answer_is_42 : 21 * 2 = 42.
Proof. reflexivity. Qed.
EOF

(cd /app && coqc my_probe.v)

cat > /app/tool_chain.ml <<'EOF'
let () = Printf.printf "42\n"
EOF

ocamlopt -o /app/tool_chain /app/tool_chain.ml
/app/tool_chain > /app/tool_chain.txt