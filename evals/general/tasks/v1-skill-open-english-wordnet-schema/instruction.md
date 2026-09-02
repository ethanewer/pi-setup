# Open English WordNet schema

`/app/wordnet_subset.json` is a subset of an **Open English WordNet (OEWN)** export in
the standard JSON schema. It contains an array of **synset** objects:

```json
{
  "synsetId": "n02084071-n",        // "<pos-letter><8-digit-id>-<pos-letter>", e.g. noun = n
  "pos": "n",                       // part of speech: n, v, a, r, s
  "lemmas": ["dog", "domestic dog", "Canis familiaris"],   // lemmas of this synset; lemmas[0] is the primary lemma
  "definition": "a member of the genus Canis ...",
  "hypernyms": ["n02075296-n"],     // ids of the IMMEDIATE superordinate (more general) synsets
  "hyponyms": ["n02098453-n"],      // ids of immediate subordinate (more specific) synsets
  "meronyms": ["n02107679-n", "n03126707-n"]   // part/constituent relations
}
```

Note that **two different synsets share the lemma `"dog"`**: the canine sense
(`n02084071-n`, definition mentions "genus Canis ... domesticated") and the food sense
(`n07865757-n`, a "frankfurter"). Both list `"dog"` in `lemmas`.

Write a Python script `/app/wordnet_probe.py` that, using this OEWN schema:

1. loads `/app/wordnet_subset.json` into a lookup by `synsetId`,
2. finds the **canine sense of "dog"** — the synset whose `lemmas` contain `"dog"` and
   whose `definition` contains the substring `"Canis"`,
3. walks the **hypernym chain** from that synset upward: repeatedly take
   `hypernyms[0]` (the primary hypernym). Stop when you reach a synset whose
   `hypernyms` list is empty (the root `n00001740-n` "entity") — **do not include that
   root synset itself in the output**,
4. writes `/app/chain.txt` with the **primary lemma** (`lemmas[0]`) of every synset on
   the chain (excluding the starting dog synset and excluding the root), one per line,
   in traversal order (immediate hypernym first).

The verifier performs the same schema-aware traversal independently and compares the
list.