/app/seq.json contains a circular sequence:

```json
{
  "seq": [<integers>],
  "queries": [<integer indexes, which may be negative, zero-based, or >= length>]
}
```

The sequence is circular, meaning indexes wrap around the boundary: index `i` addresses element `seq[i mod n]` where `n = len(seq)`, using modulo semantics so negative and oversize indexes wrap correctly into `[0, n)`.

Write `/app/wrap.py` that reads the JSON and, for each query index, computes the element at that circular position, then writes `/app/wrapped.json`:

```json
{"values": [<element for each query, in the same order>]}
```

Then run your script so `/app/wrapped.json` is produced. Use only the Python standard library.