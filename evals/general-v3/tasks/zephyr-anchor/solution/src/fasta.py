#!/usr/bin/env python3
"""Write a well-formed FASTA PAIR file from a single template FASTA.

Contract:
    python3 /app/fasta.py <template.fa> <output.fa>

Reads a FASTA file containing exactly ONE record (header + one or more sequence
lines; header description text is ignored; blank lines are ignored during
parsing; sequence may be mixed-case). Writes <output.fa> containing EXACTLY two
records, in forward-first order:

    >NAME                       <- record 1 header (first token, no '>')
    <forward sequence uppercase, wrapped at 80 columns>
    >NAME_rc                    <- record 2 header
    <reverse complement, uppercase, wrapped at 80 columns>

NAME is the first whitespace-delimited token of the template header with the
leading '>' removed. The file contains NO blank lines anywhere, every line ends
without trailing spaces, and the file ends with a single trailing newline.
Sequence characters are restricted to A/C/G/T (all uppercase on output).
Exit status 0 on success.

Reverse complement: reverse the sequence (5'->3' becomes the reverse order),
then complement each base A<->T and G<->C, always emitting uppercase.
"""

import sys

_COMP = {"A": "T", "C": "G", "G": "C", "T": "A"}
_WIDTH = 80


def revcomp(seq):
    return "".join(_COMP[ch] for ch in "".join(
        ch.upper() for ch in seq)[::-1])


def parse_single_fasta(text):
    """Return (name, sequence) for a single-record FASTA or raise ValueError."""
    name = None
    seq = []
    header_seen = False
    body_started = False
    for line in text.split("\n"):
        if line.startswith(">"):
            if header_seen:
                raise ValueError("more than one record")
            header_seen = True
            tok = line[1:].split()
            name = tok[0] if tok else ""
        else:
            if line.strip():
                seq.append(line.strip())
    if not header_seen or name == "":
        raise ValueError("missing or empty header")
    return name, "".join(seq)


def wrap(seq, width=_WIDTH):
    return [seq[i:i + width] for i in range(0, len(seq), width)] or [""]


def build_pair(name, seq):
    out = [">" + name + "\n"]
    out += [line + "\n" for line in wrap(seq.upper())]
    out += [">" + name + "_rc\n"]
    out += [line + "\n" for line in wrap(revcomp(seq.upper()))]
    return "".join(out)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: fasta.py <template.fa> <output.fa>\n")
        return 2
    in_path, out_path = argv[1], argv[2]
    with open(in_path) as fh:
        text = fh.read()
    name, seq = parse_single_fasta(text)
    seq = seq.upper()
    if not set(seq) <= set("ACGT"):
        sys.stderr.write("template contains non-ACGT characters\n")
        return 2
    with open(out_path, "w") as fh:
        fh.write(build_pair(name, seq))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))