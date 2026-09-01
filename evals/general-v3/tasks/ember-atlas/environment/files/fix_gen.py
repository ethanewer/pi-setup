#!/usr/bin/env python3
"""ember-atlas build-time fixture generation: creates the visible repo
ridge/topoline-24m under /app/hub plus a pristine-sha manifest used by the
verifier's no-modify check."""
import hashlib
import os
import sys

sys.path.insert(0, "/build")
from gen_model import make_repo  # noqa: E402

d = "/app/hub/ridge/topoline-24m"
make_repo(d, seed=7,
          extra_words=["topoline", "ridge", "sweep", "drift", "the", "ridgetop"])

lines = []
for fn in sorted(os.listdir(d)):
    with open(os.path.join(d, fn), "rb") as fh:
        h = hashlib.sha256(fh.read()).hexdigest()
    lines.append("%s  %s" % (h, fn))
with open("/app/hub_pristine.sha256", "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("fix_gen done")
