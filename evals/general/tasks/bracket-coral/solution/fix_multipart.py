#!/usr/bin/env python3
"""Fix the multipart boundary-newline corruption in the werkzeug checkout at
/app/src.

The bug: in MultipartDecoder._parse_data, when the buffered part data holds no
complete boundary yet, `self.last_newline(data[data_start:])` returns an index
relative to the *sliced* bytes but is stored into data_end/del_index, which are
absolute offsets into `data`. The fix adds data_start to that result before
storing it, so the 'data up to the partial boundary' slice ends at the correct
absolute position and the trailing newline bytes that belong to the next part /
boundary no longer leak into the returned Data event.

This is the same edit the upstream project made to fix the bug; it is authored
here as a tiny patcher so the oracle applies a real change to the real tree
rather than shipping one.
"""
import pathlib

SOURCE = pathlib.Path("/app/src/src/werkzeug/sansio/multipart.py")

TARGET = "            data_end = del_index = self.last_newline(data[data_start:])"
REPLACEMENT = [
    "            last_newline_idx = self.last_newline(data[data_start:])\n",
    "            data_end = del_index = last_newline_idx + data_start  # Adjusted index\n",
]

lines = SOURCE.read_text().splitlines(keepends=True)
hits = [i for i, line in enumerate(lines) if line.rstrip("\n") == TARGET]
assert len(hits) == 1, f"expected exactly one buggy line, found {len(hits)}"
assert not any("last_newline_idx" in line for line in lines), "fix already applied?"
i = hits[0]
lines[i : i + 1] = REPLACEMENT
SOURCE.write_text("".join(lines))
print(f"patched {SOURCE}")