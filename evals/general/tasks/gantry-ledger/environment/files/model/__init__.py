"""Deterministic simulated extractor.

The behavioural core is compiled at image build time into
`_symcore.marshal` (a marshalled code object). Only the interface below is
intended for use: `extract(prompt_text, record_text) -> dict` and the
constant `UNKNOWN`. The extractor is a pure, deterministic function of its
two arguments.
"""
import marshal
import os
import types

_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "_symcore.marshal")


def _load():
    with open(_PATH, "rb") as fh:
        code = marshal.load(fh)
    mod = types.ModuleType("simcore")
    mod.__file__ = _PATH
    exec(code, mod.__dict__)
    return mod


_SIM = _load()

extract = _SIM.extract
UNKNOWN = _SIM.UNKNOWN