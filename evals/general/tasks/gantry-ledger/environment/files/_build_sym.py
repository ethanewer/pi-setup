"""Build step: compile the simulated extractor core into a marshalled code
object so the trial container ships the model without its source."""

import marshal
import pathlib

here = pathlib.Path(__file__).resolve().parent
src = (here / "_lib.py").read_text(encoding="utf-8")
code = compile(src, str(here / "_lib.py"), "exec")
out = here / "model" / "_symcore.marshal"
out.write_bytes(marshal.dumps(code))
print("wrote", out, len(out.read_bytes()), "bytes")