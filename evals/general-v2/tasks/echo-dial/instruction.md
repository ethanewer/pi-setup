# Echo-dial relay scan

## Objective

You are inspecting a captured relay archive. The directory `/app/relay/`
contains a mixture of ordinary files and **encoded call-detail nodes**. You must
author **one reusable program**, `/app/attack.py`, that reads any such relay
directory, recovers every encoded node, and emits three output artifacts. Your
program will be re-run on **hidden** relay directories with different data, so
it must be fully general (stdlib is available; no extra packages are needed).

The program is executed as:

```
python3 /app/attack.py <input_dir> <output_dir>
```

and must:
- scan `<input_dir>`, open exactly the files that match the naming convention
  below, and skip everything else,
- write the three artifacts described below into `<output_dir>` (creating it if
  needed),
- exit with status `0`.

## The encoded-node scheme (exact)

**1. Naming.** A registered encoded node is a file whose name is

```
encoded_<X>
```

where `<X>` is the **URL-safe**, **unpadded** base64 of the *original filename*
(a.k.a. the node name). To recover the original filename:

- take the segment after the `encoded_` prefix,
- pad it with `=` characters so its length becomes a multiple of 4,
- decode it with URL-safe base64 (the character set is `A-Za-z0-9-_`).

For example, a node whose original name is `netlog.txt` would be named
`encoded_` followed by the unpadded URL-safe base64 of the plain text
`netlog.txt`. A file whose name does **not** begin with `encoded_` and then a
valid unpadded base64url segment is **not** a node and must be ignored.

**2. Body.** Each node file holds a single line of ordinary (padded) base64.
Decode that line to bytes `C[i]`. The plaintext bytes `P[i]` satisfy

```
P[i] = C[i] XOR K[i mod len(K)]
```

where `K` is the byte array of the ASCII password **`ardelle`** and `i` indexes
bytes from `0`. Decode `P` as UTF-8 to get the node's plaintext text.

**3. Malformed / unrelated files.** A relay directory may contain decoys:
files that look promising but are not valid nodes, for example files whose name
does not follow the convention, files whose name decodes to garbage, files whose
base64 body is corrupted, or a node whose decrypted bytes are not valid UTF-8.
Your program must **skip** any file it cannot fully decode and keep working on
the valid nodes. Do **not** crash; do **not** emit empty entries for them.

## Output artifacts (written into `<output_dir>`)

### `name.txt`
One **[original filename]** per line, in the order the nodes are processed:
process the files in **ascending name order** (sort the file names as strings,
then process them in that sorted order). Only decoded original names of valid
nodes are listed, one per line, ending with a final newline.

### `plaintexts.txt`
One **plaintext text per line**, in the **same order as `name.txt`** — the
`i`-th line of `plaintexts.txt` is the plaintext of the node whose original
name is the `i`-th line of `name.txt`. Trailing newlines inside each node's
plaintext are removed; the artifact itself is one line per node with a final
newline. Files that were skipped produce no line at all.

### `word.txt`
A single line containing the **secret word** (see below), final newline.

## The secret word

Exactly **one** valid node's plaintext contains the marker line

```
:::: VAULT-VERDICT :::: <TOKEN>
```

where `<TOKEN>` is a token of letters, digits and hyphens (e.g.
`SUMMIT-raIL7`). The single secret word is that `<TOKEN>` **normalised**:

- lowercase it (case-insensitively collapse to lowercase ASCII),
- drop every non-alphanumeric character (so hyphens etc. are removed),
- digits are kept.

For `SUMMIT-raIL7` the secret word is `summitrail7`. Write that one word
(for a valid node carrying the marker) as the single line of `word.txt` in
`<output_dir>`. If no node contains the marker, `word.txt` holds a single empty
line.

## Your deliverable

1. Author `/app/attack.py` as described above. It is always invoked through the
   Python interpreter (`python3 /app/attack.py <input_dir> <output_dir>`), so it
   must simply exist as a readable Python source file; it does **not** need to be
   marked executable.
2. Run it against the provided relay so the deliverables land under `/app`:

```
python3 /app/attack.py /app/relay /app
```

This must leave `/app/name.txt`, `/app/plaintexts.txt` and `/app/word.txt`
present. Do **not** delete or modify the files inside `/app/relay`; they are
needed again later.

Your `attack.py` will be re-run by the verifier on hidden relay
directories (different node names, different plaintexts, a different secret
token, and adversarial decoys) through the exact same interface
`python3 /app/attack.py <input_dir> <output_dir>`, and every artifact must
generalise — treating ordering, padding, XOR, UTF-8 failure and the
single-marker normalisation exactly as specified.

## Success criteria

The program must exit `0` on any such input directory and produce the three
artifacts in the exact formats above; the verifier independently checks name
decoding, node decryption, ordering, malformed-file skipping, and the secret
word for the visible relay and for every hidden relay.