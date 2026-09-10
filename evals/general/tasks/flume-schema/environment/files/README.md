# flume-schema mock agent platform

This directory is the fixture for a tool-calling exercise. You write the
executor loop (`/app/agent_loop.py`); this platform is fixed and correct.

- `registry.json` — the JSON-schema registry for the 6 tools. Each tool has
  `name`, `description`, `idempotent` (bool) and `parameters` (JSON-schema
  subset: `type`, `minimum`, `maximum`, `maxLength`, `minItems`, `items`,
  `required`).
- `runtime/protocol.py` — feedback type tokens (`EXECUTED`, `REPLAYED`,
  `MALFORMED`, `SCHEMA_ERROR`, `UNKNOWN_TOOL`, `EXEC_ERROR`) and the retry
  constants `MAX_EXEC_RETRIES = 3`, `RETRY_BASE_DELAY_SEC = 0.05`.
- `runtime/registry.py` — `ToolRegistry`: `names()`,
  `is_idempotent(name)`, `validate(name, args)` -> canonical
  `SCHEMA_ERROR:<tool>:<path>:<constraint>:<value>` or `None`.
- `runtime/backend.py` — `Store(transcript)`: `execute(name, args)` returns
  the result dict or raises `ToolError(code, detail, retryable)`;
  `snapshot()` returns the deterministic final state.
- `runtime/models.py` — `MockModel(transcript)`: pure function of your
  feedback history; emits tool calls and final answers.
- `transcripts/session_A.json` — the visible session transcript.

The deliverable's full contract is given in the task instruction (the prompt
you were handed — a copy is not stored in the container); the short version
here: drive the model inside `max_steps`, validate every well-formed call with
the registry, never execute malformed/unknown/unschemaed calls, replay
duplicates of non-idempotent tools, silently retry `GATEWAY_BUSY` up to
`MAX_EXEC_RETRIES`, and write the run log JSON.  If you have not been given an
instruction text, ask for it before writing anything.