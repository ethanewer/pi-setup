# Construct assembler and primer designer

A synthetic-biology bench needs a deterministic construct assembler. Write
`/app/solve.py`, then run it on the visible inputs to produce
`/app/answer.json` and `/app/constructs.fasta`. Do not modify the input files.
Your program will also be run on unseen inputs with the same contract, so it
must be fully general.

## CLI contract

```
python3 solve.py CONSTRUCT_JSON CODONS_JSON NAME ANSWER_OUT FASTA_OUT
```

Five positional arguments, exactly. It reads the two JSON inputs and writes the
two output files. It must exit nonzero on malformed inputs (missing keys,
unknown part names in the order, amino-acid letters absent from the codon
table).

## Inputs

`CONSTRUCT_JSON` has the shape:

```json
{"domains": {"D1": "MKTVC", ...}, "linkers": {"L0": "GGS", ...},
 "order": ["D1", "L0", "D2"]}
```

`CODONS_JSON` maps every single-letter amino-acid code (20 letters) plus `"*"`
to one DNA codon each.

## Assembly rules (all deterministic)

1. Protein: concatenate the amino-acid strings of the parts named by `order`
   (domains and linkers interleaved exactly as listed).
2. Coding DNA: reverse-translate the protein codon by codon using
   `CODONS_JSON`.
3. FASTA output (`FASTA_OUT`): first line `>construct|NAME|len=<protein
   length>`, then the DNA wrapped at exactly 60 characters per line, and a
   trailing newline after the final line. No other bytes.
4. GC content: `(G + C) / len(dna)` rounded to 4 decimal places
   (Python `round`).
5. Primers (Golden-Gate convention). Fixed arm prefix `GGTCTCN`
   (recognition site plus one spacer base). A primer body is the first `m`
   bases of the sequence being primed:
   - forward body: first `m` bases of the coding DNA;
   - reverse body: first `m` bases of the reverse complement of the coding DNA.
   The smallest `m` in `[15, 28]` is chosen such that ALL of:
   - melting temperature `Tm = 2*(A+T) + 4*(G+C)` of the body lies in
     `[50, 72]` inclusive;
   - the body contains no homopolymer run longer than 4 identical bases;
   - the last base of the body is `G` or `C` (GC clamp).
   Each primer sequence is `GGTCTCN + body`. Inputs are guaranteed to admit a
   solution; if none exists, exit nonzero.

## `/app/answer.json` schema (exact keys)

```json
{
  "protein": "<assembled amino-acid sequence>",
  "dna": "<coding sequence>",
  "gc_content": <number, 4 decimals>,
  "fasta_sha256": "<sha256 hex of the FASTA output file bytes>",
  "primers": [
    {"name": "F", "seq": "<full primer>", "tm": <body Tm>, "body_len": <m>},
    {"name": "R", "seq": "<full primer>", "tm": <body Tm>, "body_len": <m>}
  ]
}
```

`tm` and `body_len` describe the body only, not the arm.

## Visible deliverables

Run your program on `/app/construct.json` with `/app/codons.json`, name
`visible`, writing `/app/answer.json` and `/app/constructs.fasta`.

## Edge cases the checker probes

- different domain/linker counts and orders;
- parts where short bodies violate the Tm window, homopolymer, or GC-clamp
  rules (your selection loop must advance `m`);
- exact byte comparison of both outputs, including the FASTA wrapping and
  trailing newline, and the self-reported `fasta_sha256`.
