/app/rle.json contains a segmentation mask in COCO RLE format:

```json
{"size": [<height>, <width>], "counts": [<int>, <int>, ...]}
```

In the COCO RLE convention the mask is stored row-major flattened (height rows of width pixels, total `height * width` values). `counts` is a run-length list: the first number is the count of leading `0`s, then alternating runs of `1`s and `0`s. Decoding reconstructs the binary mask:

```
bit = 0; position = 0
for each run length c in counts:
    set the next c pixels of the flattened mask to bit
    position += c
    bit = 1 - bit      (toggle)
```

Write `/app/decode.py` that reads the JSON, decodes the mask, and writes `/app/mask.json`:

```json
{
  "mask": [[<0 or 1>, ... row of width>, ... one row per height],
  "area": <integer, the total number of 1 pixels>
}
```

Then run your script so `/app/mask.json` is produced. Use only the Python standard library.