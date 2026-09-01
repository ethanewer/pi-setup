# Tensor partitioning (sharding)

A tensor of shape **(64, 8)** with `int64` values is stored in NumPy format at `/app/features.npy`. You can load it with:

```python
import numpy as np
tensor = np.load("/app/features.npy")
```

## Your Task

Partition (shard) this tensor along its **first axis** (rows, length 64) into **4 contiguous, equal-sized shards**, each of shape `(16, 8)`. Save the shards as the files:

- `/app/shards/shard_0.npy`
- `/app/shards/shard_1.npy`
- `/app/shards/shard_2.npy`
- `/app/shards/shard_3.npy`

where shard `k` is rows `[k*16 : (k+1)*16]` of the original tensor. The directory `/app/shards/` does not exist yet — create it.

The shards must reconstruct the original tensor **exactly** when concatenated in order:

```python
import numpy as np
original = np.load("/app/features.npy")
shards = [np.load(f"/app/shards/shard_{i}.npy") for i in range(4)]
assert np.array_equal(np.concatenate(shards, axis=0), original)
```

## Verification

- `/app/shards/` contains exactly the four files `shard_0.npy` … `shard_3.npy`.
- Each shard has shape `(16, 8)` and integer dtype.
- Concatenating them along axis 0 reproduces `/app/features.npy` exactly.

Use a small Python/NumPy script to perform the partition. Save the shards to exactly the paths above.