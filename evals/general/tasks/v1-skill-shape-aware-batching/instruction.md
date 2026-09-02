# Batch variable-size items into the minimum number of groups (shape-aware batching)

## Context

`/app/items.json` is a list of items, each with a `name` and a `size` (a
positive integer). In this inference-style scheduler, a batch may hold at most
**32** total size. Group every item into batches so that:

- every item appears in **exactly one** batch,
- the sum of sizes in each batch is **≤ 32**,
- the number of batches is **minimal**.

## Your task

Write a small Python script (or use `python3 - <<` heredoc) that reads
`/app/items.json`, packs the items, and writes `/app/out/batches.json`:

```json
[ ["a", "b"], ["c", "d", "e", "f"], ["g", "h", "i", "j", "k", "l"] ]
```

The file is a list of batches; each batch is a list of item names. The order of
batches and of items inside a batch does not matter — only validity and the
batch count matter. A valid 3-batch solution exists (the total size is 88 and
no batch may exceed 32, so fewer than 3 is impossible).

## Success criteria

- `/app/out/batches.json` exists and is a list of batches.
- Every item is placed exactly once; every batch sum ≤ 32.
- The number of batches equals the minimum possible (3).