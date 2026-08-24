#!/bin/bash
# Oracle solution for skill-ocaml-runtime.
set -euo pipefail

cat > /app/sum.ml <<'EOF'
let () =
  let ic = open_in "/app/input.txt" in
  let rec read acc =
    try read (acc + int_of_string (input_line ic))
    with End_of_file -> acc
  in
  let s = read 0 in
  close_in ic;
  Printf.printf "%d\n" s
EOF

ocamlopt -o /app/sum /app/sum.ml
/app/sum > /app/answer.txt