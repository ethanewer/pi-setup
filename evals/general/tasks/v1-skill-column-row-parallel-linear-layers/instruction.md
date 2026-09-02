/app/layers.json contains the weight matrices of two linear layers, together with tensor-parallel partitioning instructions.

A linear layer weight matrix `W` has shape `[in_features, out_features]` (row index = input feature, column index = output feature). When the layer is sharded across `num_tiles` tiles there are two partition schemes:

- **column-parallel**: the `out_features` (column) dimension is split into `num_tiles` contiguous chunks. Tile `t` (0-based) owns columns `[t*out/num_tiles : (t+1)*out/num_tiles]` — i.e. the shard is `W[:, lo_col:hi_col]`. Each tile computes part of each output unit; results are concatenated along the output dimension.
- **row-parallel**: the `in_features` (row) dimension is split into `num_tiles` contiguous chunks. Tile `t` owns rows `[t*in/num_tiles : (t+1)*in/num_tiles]` — i.e. the shard is `W[lo_row:hi_row, :]`. Each tile computes a partial (accumulated) result over its chunk of inputs.

`num_tiles` always divides the relevant dimension evenly.

Write `/app/split.py` that reads the JSON and, for every layer, produces the weight shard allocated to that layer's `tile_id`, then writes `/app/shard.json`:

```json
{
  "<layer name>": {"shard": <<the tile's 2D list of numbers, rows preserved>>},
  ...
}
```

Then run your script so `/app/shard.json` is produced. Use only the Python standard library.