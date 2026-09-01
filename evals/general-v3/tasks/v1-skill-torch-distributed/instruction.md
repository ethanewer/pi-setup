# A distributed reduce with torch.distributed

`/app/values.txt` contains a single line of whitespace-separated decimal
integers. The container has PyTorch installed (CPU build), which includes the
`torch.distributed` package.

Write a Python script `/app/distributed.py` that:

1. Initializes a default `torch.distributed` process group using the **gloo**
   backend and `tcp://127.0.0.1:29500` as the init method, with `rank=0`,
   `world_size=1` (a single process; the process group has one member).
2. Builds a `torch.float64` tensor from the integers in `/app/values.txt`.
3. Performs an `allreduce` over the (single-member) process group using the
   **SUM** reduction operation, exactly once.
4. Computes the total (the sum of the reduced tensor's elements).
5. Writes `/app/result.json` containing exactly:

```json
{"total_sum": X}
```

where `X` is the total rounded to 4 decimal places.
6. Destroys the process group before exit.

The verifier independently runs the `allreduce` over the same single-member
process group and accepts any `total_sum` within 0.0001 of its own value.