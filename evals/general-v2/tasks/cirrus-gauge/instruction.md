# Cirrus-Gauge: configure a Caffe-style training run

The **Cirrus-Gauge** cloud-optics team trains a small image classifier with a
Caffe-style pipeline. Your job is to author the training **configuration
artifacts**: a solver definition plus train and test network definitions in
prototxt format, produced by a reusable generator program. The training itself
is out of scope; the configuration must be *structurally valid*, run in **CPU
mode**, and use a **capped iteration count**.

Everything happens in `/app` with Python 3.12 standard library only.

## Provided fixtures (do not modify)

- `/app/data/mini/train_list.txt` — training image list (`<file> <label>` per line).
- `/app/data/mini/test_list.txt` — test image list, same format.

## Deliverable 1: `/app/gen_config.py`

A reusable CLI generator:

```
python3 /app/gen_config.py <data_root> <max_iter> <batch> <out_dir>
```

Behavior (must hold for **any** valid arguments, not just the visible ones):

- `<data_root>` and `<out_dir>` are directory paths; resolve both to absolute
  paths (a trailing slash or a relative path must still work). Create
  `<out_dir>` if it does not exist.
- `<max_iter>` and `<batch>` are integers. If either is missing, non-integer,
  or <= 0, the program must print an error to stderr and **exit non-zero**
  without writing any file.
- It writes exactly three files into `<out_dir>`:
  `solver.prototxt`, `train_net.prototxt`, `test_net.prototxt` (format below).
- It must be **deterministic**: running it twice with identical arguments
  produces byte-identical files.

### `train_net.prototxt` (required structure)

A prototxt net named `GaugeTrain` with these layers (names must be unique):

1. A data layer named `data` of type `ImageData` with tops `data` and `label`,
   an `include { phase: TRAIN }` block, and an `image_data_param` block where
   `source` is the **absolute path** `<data_root>/train_list.txt` and
   `batch_size` equals `<batch>`.
2. At least one `Convolution` layer.
3. Optionally any other intermediate layers (`Pooling`, `ReLU`, `InnerProduct`, ...).
4. A loss layer of type `SoftmaxWithLoss`.

### `test_net.prototxt` (required structure)

A prototxt net named `GaugeTest` with:

1. A data layer named `data` of type `ImageData` with
   `include { phase: TEST }`, `source` = absolute `<data_root>/test_list.txt`,
   `batch_size` = `<batch>`.
2. The same trunk as the train net (at least one `Convolution` layer).
3. An `Accuracy` layer.
4. A `SoftmaxWithLoss` layer.

Layer names must be unique within each file.

### `solver.prototxt` (required structure)

A prototxt solver containing exactly these keys:

- `net` — the absolute path of the generated `train_net.prototxt` inside `<out_dir>`;
- `test_net` — the absolute path of the generated `test_net.prototxt` inside `<out_dir>`;
- `test_iter` — a positive integer (e.g. the test list length divided by `<batch>`, rounded up);
- `test_interval` — a positive integer;
- `base_lr` — a positive float (e.g. `0.01`);
- `momentum` — e.g. `0.9`; `weight_decay` — e.g. `0.0005`;
- `display` — a positive integer;
- `max_iter` — `min(<max_iter>, 1000)` (**the iteration cap**: a requested
  value above 1000 must be clamped to 1000);
- `snapshot_prefix` — a path inside `<out_dir>` (e.g. `<out_dir>/gauge`);
- `solver_mode: CPU` (the run must be CPU-mode);
- `solver_type: SGD`.

## Deliverable 2: the visible configuration

Run your generator with the shipped parameters:

```
python3 /app/gen_config.py /app/data/mini 400 16 /app/out
```

and leave the three generated files in place:

- `/app/out/solver.prototxt`
- `/app/out/train_net.prototxt`
- `/app/out/test_net.prototxt`

## What the checker enforces

The checker parses the prototxt files (comments with `#`, `key: value` pairs
and nested `key { ... }` blocks) and enforces the structure above — for the
visible configuration **and** for fresh runs of `/app/gen_config.py` with
unseen parameters, including:

- a different data root, batch sizes like `1` and `64`, and requested
  `max_iter` values both below and **above** the 1000 cap (must clamp);
- `solver_mode` must be `CPU` and the cap must hold in every generated solver;
- data-layer `source` paths must point into the data root given for that run;
- `batch_size` must propagate into both data layers;
- byte-identical output when the same arguments are run twice;
- invalid arguments (e.g. a zero or negative `max_iter`/`batch`, or a missing
  argument) must exit non-zero and leave no `solver.prototxt` behind in the
  output directory.

A solver not set to CPU mode, an unclamped iteration count, or nets whose data
layers disagree with the requested data root / batch fail the check.

## Constraints

- Do not modify `/app/data/mini/*`.
- Standard library only; deterministic; no network. You may keep helper files
  under `/app`, but the checker needs only `/app/gen_config.py` and the three
  files in `/app/out`.
