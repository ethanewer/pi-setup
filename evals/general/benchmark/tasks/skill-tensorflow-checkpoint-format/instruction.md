# TensorFlow checkpoint format

TensorFlow saves a model checkpoint not as a single file but as a **group of files sharing a common prefix**. For a checkpoint saved with the prefix `model`, the on-disk layout is:

- `checkpoint` — a pointer/meta text file containing the line `model_checkpoint_path: "model"` (this tells the loader where the checkpoint group is).
- `model.index` — the index (variable names and byte offsets) for the checkpoint group.
- `model.data-00000-of-00001` — the actual sharded variable values (here 1 of 1 data shards).

## Your Task

Create a **valid checkpoint group** for a model checkpoint named `model` in the directory `/app/checkpoint/` (create the directory if it does not exist). You must produce the three files described above with exactly these names:

1. `/app/checkpoint/checkpoint` — containing the exact text `model_checkpoint_path: "model"` on its own line.
2. `/app/checkpoint/model.index` — can be placeholder bytes (any content).
3. `/app/checkpoint/model.data-00000-of-00001` — can be placeholder bytes (any content).

The point of this task is to demonstrate the correct TensorFlow checkpoint **file-group naming/layout**. You do not need TensorFlow installed; just create the correctly named files. Placeholders are fine for the binary files.

## Verification

- The three files exist with the exact names above.
- `/app/checkpoint/checkpoint` contains the line `model_checkpoint_path: "model"`.
- No additional `model.*` checkpoint files are required.

Create the files at exactly these paths.