In `/app` there is a local helper module `fetch_pdb.py` that mimics a single RCSB (Protein Data Bank) API record fetch for a protein entry. It defines:

```python
def fetch_pdb(pdb_id): ...
```

Calling `fetch_pdb('3abc')` returns a dictionary with this shape:

```json
{
  "rcsb_id": "3abc",
  "struct": {"title": "...", "n_residues": <int>, "resolution": <float>},
  "entities": [{"kind": "...", "n_atoms": <int>}, ...]
}
```

Write a Python script `/app/report.py` that:

1. Calls `fetch_pdb('3abc')` to obtain the structure record.
2. Computes:
   - `residues` = the integer value of `struct.n_residues`
   - `atoms` = the total number of atoms, i.e. the sum of `n_atoms` over every entity in `entities`
3. Writes `/app/answer.txt` containing exactly one line:

```
atoms <atoms> residues <residues>
```

For example, if the record had 3 residues and two entities with 1 and 2 atoms, the line would be `atoms 3 residues 3`.

Run the script so `/app/answer.txt` exists with the correct values.