At `/app/packed.dat` is a file produced by a fictional custom compressor. Every line is a run record with the form:

```
<count> <hex-byte>
```

where `<count>` is a decimal integer (1 or more) and `<hex-byte>` is a two-digit lowercase-hex byte value (e.g. `6c`). The meaning of a line is: **emit that byte value, `<count>` times**.

To decompress, read the lines in file order and concatenate all the emitted bytes into one contiguous byte stream. That stream is the original uncompressed content. In this task the original content happens to be readable ASCII text.

Write `/app/decompress.py` that reads `/app/packed.dat`, applies this rule, and writes the recovered text to `/app/unpacked.txt`.

Then run your script. The recovered text is a single space-separated phrase (some shorter English words). Do not add extra text; the verifier recomputes the decompressed bytes itself from `/app/packed.dat` and compares them to `/app/unpacked.txt`.