A small combinational digital circuit over boolean (0/1) signals is described at `/app/circuit.json`:
```json
{"inputs":["x","y"],
 "nodes":[{"id":"n1","op":"OR","in":["x","y"]},
          {"id":"n2","op":"AND","in":["n1","y"]},
          {"id":"out","op":"NOT","in":["n2"]}],
 "outputs":["out"]}
```
`inputs` are the available input signal names. Each node has an id, an op from `{"AND","OR","XOR","NOT"}`, and an `in` list of the node ids / input names it reads. Nodes are listed in topological order (all dependencies first). `outputs` is a list of node ids whose values you must report.

Also given is `/app/assignments.json`, a JSON array of input assignments, e.g. `[{"x":1,"y":1},{"x":1,"y":0}]`.

Write a program `/app/eval_circuit.py` that:
1. loads both files,
2. evaluates the circuit bit by bit (evaluate each node using the boolean/bitwise interpretation; e.g. NOT(x)=1-x, AND is logical AND of 0/1 values, etc.),
3. for every assignment, records the value of each node listed in `outputs`,
4. writes `/app/outputs.json` as a JSON array with one entry per assignment, each entry being a list of integer output values in the order of `outputs`.

Run your program so the output file is produced. The verifier recomputes the same gate evaluations.
