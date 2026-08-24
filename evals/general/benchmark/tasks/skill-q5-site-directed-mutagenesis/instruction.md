# Site-directed DNA mutagenesis (DNA editing)

You are performing an in silico analog of Q5 site-directed mutagenesis: applying precisely located nucleotide substitutions to a DNA sequence.

- `/app/dna.txt` contains a single DNA string (characters from `A/C/G/T`, no spaces, no newlines within). It is the **0-indexed** source sequence.
- `/app/mutations.txt` contains one mutation per line, format: `<i> <old> <new>` where:
  - `i` is a 0-based character index into the DNA string
  - `old` is the nucleotide currently at that position in `/app/dna.txt` (verify it matches)
  - `new` is the replacement nucleotide you must put at that position

Apply every mutation to a copy of the DNA string (positions are applied relative to the original string, but since each mutation targets a distinct index, order does not matter). Write the resulting mutated DNA string with **no separators** (uppercase, exact) to `/app/mutated.txt` (no trailing newline required).

Write the editing script as `/app/mutate.py` and run it so `/app/mutated.txt` is produced.
