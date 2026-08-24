You are given a list of overlapping **fragments** of a longer string, and you must reassemble the original string by stitching the fragments back together.

In `/app` there is `/app/fragments.txt` — a text file with one fragment per line. The fragments overlap each other such that the correct full string can be reconstructed by ordering them by maximal suffix-prefix overlap.

For example, if the correct reconstruction is `"abcdefgh"` and fragments are `"abcde"`, `"cdef"`, `"efgh"`, then joining `"abcde"` + `"cdef"` (overlap `"cd"`) gives `"abcdef"`, then + `"efgh"` (overlap `"ef"`) gives `"abcdefgh"`.

Write `/app/reassemble.py` that:
1. Reads all fragment lines from `/app/fragments.txt` (a newline-delimited file, no blank trailer line).
2. Reconstructs the single best original string by repeatedly adjoining the fragment with the **longest** suffix-prefix overlap (if two have equal overlap, pick the one that appears first in file order). A fragment may only be used once.
3. Writes the reconstructed string (with no trailing newline) to `/app/original.txt`.

Run your script so `/app/original.txt` contains the correct full string. Use `python3`.