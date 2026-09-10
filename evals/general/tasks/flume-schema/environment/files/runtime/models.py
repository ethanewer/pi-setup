"""runtime.models — the deterministic mock model.

The mock model is a pure function of the conversation history it has seen.
Each feedback message the loop appends is `<TYPE>:<payload>`; the model maps
the TYPE token to a one-letter category:

    EXECUTED -> K   REPLAYED -> R   MALFORMED -> M
    SCHEMA_ERROR -> S   UNKNOWN_TOOL -> U   EXEC_ERROR -> E

and keys its decision table on the category-letter string of ALL tool
messages so far (the "outcome prefix").  transcript["decisions"] is a list of
[prefix, emission] pairs; the model emits the emission whose prefix is the
longest match for the current outcome prefix.  Emissions are either tool calls

    {"kind": "tool_call", "name": "...", "arguments": {...}}

or a final answer

    {"kind": "final", "answer": "..."}.

An outcome prefix with no matching decision entry is a script error: the model
raises MockFailure so a non-conforming executor cannot limp along unnoticed.
"""

from __future__ import annotations

CATEGORY_LETTERS = {
    "EXECUTED": "K",
    "REPLAYED": "R",
    "MALFORMED": "M",
    "SCHEMA_ERROR": "S",
    "UNKNOWN_TOOL": "U",
    "EXEC_ERROR": "E",
}


class MockFailure(Exception):
    """The mock model has no decision for this outcome prefix."""


class MockModel:
    def __init__(self, transcript):
        self._table = {}
        for prefix, emission in transcript.get("decisions", []):
            self._table[str(prefix)] = emission

    def next(self, messages):
        prefix = self._classify(messages)
        best, best_len = None, -1
        for key, emission in self._table.items():
            if prefix.startswith(key) and len(key) > best_len:
                best, best_len = emission, len(key)
        if best is None:
            raise MockFailure("no mock-model decision for outcome prefix %r" % prefix)
        return best

    @staticmethod
    def _classify(messages):
        letters = []
        for msg in messages:
            if msg.get("role") != "tool":
                continue
            content = msg.get("content") or ""
            tag = content.split(":", 1)[0]
            letters.append(CATEGORY_LETTERS.get(tag, "?"))
        return "".join(letters)