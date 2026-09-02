# ARC-AGI task data format

`/app/arc_task.json` holds a single task in the **ARC-AGI** JSON format. An ARC task is a JSON object with (optionally) a `name` and two arrays:

- `train`: a list of **training examples**, each `{"input": <grid>, "output": <grid>}`.
- `test`: a list of **test examples**, each `{"input": <grid>, "output": <grid>}`.

A grid is a 2D array (list of lists) of color integers in the closed range `0`..`7`. All rows of a grid have the same length.

Read `/app/arc_task.json` and compute five facts about it:

1. `first_train_input_rows` — number of rows in the `input` grid of the **first** training example.
2. `first_train_input_cols` — number of columns in the `input` grid of the **first** training example.
3. `first_train_input_colors` — sorted ascending list of the distinct integer colors present in that first training input grid.
4. `num_train_examples` — number of entries in the `train` array.
5. `num_test_examples` — number of entries in the `test` array.

Write these to `/app/answer.json`:

```json
{
  "first_train_input_rows": 2,
  "first_train_input_cols": 3,
  "first_train_input_colors": [0, 1, 2],
  "num_train_examples": 2,
  "num_test_examples": 1
}
```

Use values computed from the actual file contents.