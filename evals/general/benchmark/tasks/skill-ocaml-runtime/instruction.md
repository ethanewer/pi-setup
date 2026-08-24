# OCaml program: read numbers, print their sum

`/app/input.txt` contains **5 integers**, one per line (all positive).

Write an **OCaml** program `/app/sum.ml` that:

1. reads the 5 integers from `/app/input.txt` (use `open_in` / `input_line` /
   `int_of_string`, or `Scanf`),
2. computes their **sum**,
3. prints the sum to stdout followed by a newline (e.g. `Printf.printf "%d\n" s`).

Then **compile it with the native OCaml compiler** (`ocamlopt` is installed):

```bash
ocamlopt -o /app/sum /app/sum.ml
```

and run the compiled binary, redirecting its output:

```bash
/app/sum > /app/answer.txt
```

`/app/answer.txt` must contain exactly the integer sum followed by a newline. The
verifier recomputes the sum from `/app/input.txt` independently.