# skill-solver-configuration — fill in a Caffe 1.0 solver.prototxt

`/app/solver.prototxt` is a Caffe **solver** config with several fields left as
`TBD`. Your job: **complete the solver configuration**, replacing every `TBD`
with a consistent, valid value. This is a text-editing task — Caffe is not run.

## Context

You train a plain CNN (image classifier) in Caffe 1.0 with:
- 10,000 test images, test batches of 100 → 100 test batches per test phase;
- 200,000 training images at a batch size of 256;
- a staircase (step) learning-rate schedule.

## Fill these `TBD` fields

| field                       | required value                      |
|-----------------------------|-------------------------------------|
| `test_iter`                 | `100`                               |
| `test_interval`             | `500`                               |
| `base_lr`                   | `0.01`                              |
| `max_iter`                  | `20000`                             |
| `lr_policy`                 | `"step"`                            |
| `gamma`                     | `0.1`                               |
| `stepsize`                  | `8000`                              |
| `momentum`                  | `0.9`                               |
| `weight_decay`              | `0.0005`                            |
| `snapshot`                  | `2000`                              |
| `solver_mode`               | `"GPU"`                             |

Leave all other lines exactly as they are (`type: "SGD"`, `display: 20`,
`snapshot_prefix: "snap"`, and the `train_net`/`test_net` names are fine).

## Output

Write the completed config back to **`/app/solver.prototxt`**. Keep Caffe 1.0
solver plaintext format: `key: value` one per line, numeric values bare, and
string fields quoted as shown above.

## Success criteria (verifier)

The grader parses `/app/solver.prototxt` and requires every one of the 11
fields above to carry exactly the value listed (including quotes for the two
string fields). All must match for credit.