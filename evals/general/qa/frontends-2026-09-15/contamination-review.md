# Contamination review

Reviewer: parent-codex-qa (independent of the task-authoring CLI sessions).

The frozen Terminal-Bench checkout verified at commit
`1a6ffa9674b571da0ed040c470cb40c4d85f9b9b`, 241 tasks, and content digest
`5b144a6924a3cae13f5bce0a824fb2b0dccc7efae1e45406f933158afa6886da`.
The first completed audit is retained in `contamination-raw/`.

It found zero exact files, text n-grams, canaries, source-repository overlaps, or
instruction-similarity pairs. Two hard block flags concerned the Rich long-line
input and its expected output. Inspection of every aligned hard block against
the decompressed SQLite source archive found exactly one distinct 64-byte block
in each file, identical in both cases:

```text
0123456789012345678901234567890123456789012345678901234567890123
```

This is an ordinary repeated-digit test string, independently generated in the
recorded authoring session to exercise long literal output. It carries no task
objective, algorithm, patch, answer, or distinctive source material. The source
repositories, behaviors, and verifiers are unrelated. The task was not changed
in response to this comparison. QA now recognizes only this exact 64-byte
primitive as boilerplate; it does not exempt surrounding text, whole files,
arbitrary digit strings, or other reference content. A regression test checks
that adding distinctive surrounding text does not gain this exemption.

Two 32-byte soft matches were also reported: the Freezegun dependency-install
Dockerfile and an unchanged PyYAML CI utility. These are build/Python idioms;
the PyYAML file is byte-identical to its recorded upstream revision. No hard
code or prose match accompanies either soft flag.

The final audit in `contamination/` reruns the unchanged candidate packages with
the narrow reviewed primitive rule. Its fingerprints identify the exact reviewed
packages. Reference content and audit reports stayed in QA, outside all task
authoring and pilot contexts.
