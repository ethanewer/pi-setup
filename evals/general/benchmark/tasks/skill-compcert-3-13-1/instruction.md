CompCert is a formally-verified C compiler: it compiles a substantial, well-defined subset of the C language into correct assembly code. It is famous as one of the few compilers that carries a machine-checked proof that the generated executable behaves exactly as specified by the source C program.

Question: Which interactive theorem prover is CompCert's correctness argument formalized in and mechanically checked by?

Write your answer into `/app/answer.txt` as a single line containing exactly the name of that theorem prover (e.g. `Isabelle` or `Lean`). The verifier parses the file and compares it (case-insensitively) to the canonical answer.