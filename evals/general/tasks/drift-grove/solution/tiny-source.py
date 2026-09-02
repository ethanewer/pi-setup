#!/usr/bin/env python3
"""Grove micro-pipeline pixel source (must stay tiny, may not embed pixels).

Renders a 24x40 ASCII field by arithmetic only - no pixel literals.
Writes nothing, prints exactly 24 lines of 40 chars.
"""
S = " .:-=+*#%@"
for y in range(24):
    row = "".join(S[(y * 19 + x * 7 + (y * x * 5) % 11) % 10] for x in range(40))
    print(row)