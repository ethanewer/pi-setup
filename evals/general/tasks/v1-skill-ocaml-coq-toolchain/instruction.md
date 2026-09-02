# The OCaml / Coq toolchain

Both the **Coq** proof assistant (`coqc`) and the **OCaml** native compiler (`ocamlopt`)
are installed. Demonstrate that you can drive each tool.

## Part 1 — Coq (`coqc`)

Write a Coq source file `/app/my_probe.v` that states and proves this lemma (Coq's
`nat` arithmetic `21 * 2` reduces to `42`, so `reflexivity.` finishes the proof):

```coq
Lemma answer_is_42 : 21 * 2 = 42.
Proof. reflexivity. Qed.
```

Then compile it with the Coq compiler:

```bash
coqc /app/my_probe.v
```

This must succeed (it writes `/app/my_probe.vo` / `.glob`). Do not add
`Admitted` / `Admit` / `Axiom` / `Require` to the file.

## Part 2 — OCaml (`ocamlopt`)

Write an OCaml source file `/app/tool_chain.ml` that prints the characters `42`
followed by a newline, e.g.:

```ocaml
let () = Printf.printf "42\n"
```

Compile it to a native binary and run it:

```bash
ocamlopt -o /app/tool_chain /app/tool_chain.ml
/app/tool_chain > /app/tool_chain.txt
```

`/app/tool_chain.txt` must contain `42` (and a newline).

After both parts, `/app/my_probe.v`, `/app/my_probe.vo`, `/app/tool_chain.ml` and
`/app/tool_chain.txt` must all exist.