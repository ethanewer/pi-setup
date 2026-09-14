#!/usr/bin/env python3
"""Oracle helper: apply the one-file fix to librosa/display.py in /app/src.

The tree is pinned at the parent commit, so the surrounding text is
deterministic. We surgically replace the diverging-cmap detection block with
the diverging-plus-boolean version (exactly the upstream fix) and fail loudly
if any anchor is missing.
"""
import ast
import sys
from pathlib import Path

target = Path("/app/src/librosa/display.py")
src = target.read_text(encoding="utf-8")

old1 = """        if is_diverging_cmap:"""
new1 = """        if isinstance(cmap_bool, colors.Colormap):
            is_boolean_cmap = kwargs["cmap"] == cmap_bool
        else:
            is_boolean_cmap = kwargs["cmap"] == mcm.get(cmap_bool, None)
        # Harden this check to ensure that it only hits when
        # data is really boolean
        is_boolean_cmap &= (data.dtype.kind == "b")

        if is_diverging_cmap:"""

old2 = """                ),
            )

    kwargs.setdefault("rasterized", True)"""
new2 = """            ),
        )
        elif is_boolean_cmap:
            # If we have an inferred boolean colormap, use a boundary norm
            # But only if the user didn't also set their own normalizer
            kwargs.setdefault(
                "norm",
                colors.BoundaryNorm(
                    boundaries=[0, 0.5, 1], ncolors=kwargs["cmap"].N
                ),
            )

    kwargs.setdefault("rasterized", True)"""

if "is_boolean_cmap" in src:
    print("fix already applied in /app/src/librosa/display.py")
    sys.exit(0)

if src.count(old1) != 1:
    raise SystemExit("anchor1 (diverging cmap check) not found exactly once")
if src.count(old2) != 1:
    raise SystemExit("anchor2 (rasterized setdefault) not found exactly once")

src = src.replace(old1, new1, 1)
src = src.replace(old2, new2, 1)
ast.parse(src)  # syntax check before writing
target.write_text(src, encoding="utf-8")
print("applied boolean BoundaryNorm fix to /app/src/librosa/display.py")