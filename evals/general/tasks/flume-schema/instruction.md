# flume-schema: a tool-calling executor loop against a mock model

You are handed a working **mock agent platform** for tool calling: a 6-tool
JSON-schema registry, a deterministic scripted "model" that produces tool
calls, and a deterministic in-memory tool store. What does NOT exist yet is
the **executor loop** that drives them — the code that turns each model
emission into a validated, safely executed tool call with typed feedback. You
must write it, as a single self-contained Python program `/app/agent_loop.py`.

There is nothing to fix or debug in the platform; the platform is correct and
must not be modified. A correct manager loop is the only delivered thing.

## Environment (what you start with)

Everything lives under `/app`:

| path | contents |
|---|---|
| `/app/registry.json` | the JSON-schema tool registry (6 tools) |
| `/app/runtime/` | the platform package — `protocol.py`, `registry.py`, `backend.py`, `models.py` (documented below) |
| `/app/transcripts/session_A.json` | the visible session transcript (a fixture) |
| `/app/README.md` | short platform guide (same contract as this file) |

Python 3.12, standard library only. No pip packages are or will be installed;
the loop must use only the stdlib plus the shipped `runtime` package. No
network is available. The six tools and their JSON schemas are listed below;
the observable behaviour of the store is what the grader checks, so read the
schemas and the runtime source before writing anything.

```
place_order        item_id:int(>=1), qty:int(1..5)            NOT idempotent
search_menu        query:string(<=40), max_results:int(1..10) idempotent
get_stock          item_id:int(>=1)                           idempotent
charge_card        order_id:int(>=1), amount:number(>=0.01)   NOT idempotent
send_notification  recipient:string(<=64), text:string(<=140) NOT idempotent
finalize_order     order_ids:array(>=1) of int                NOT idempotent
```

## The runtime API you build on

- `runtime.protocol` — the feedback-message type tokens, and the retry-policy
  constants `MAX_EXEC_RETRIES` (3) and `RETRY_BASE_DELAY_SEC` (0.05). **Read
  the constants from this module; do not redefine them.**
- `runtime.registry.ToolRegistry(path="/app/registry.json")` —
  `names()` (tool names in registry order), `is_idempotent(name)` and
  `validate(name, args)` which returns `None` for a schema-valid call, else a
  **canonical** `SCHEMA_ERROR:<tool>:<path>:<constraint>:<value>` string,
  e.g. `SCHEMA_ERROR:place_order:qty:maximum:5`. The canonical strings are
  stable; feed them back verbatim.
- `runtime.backend.Store(transcript)` — `execute(name, args)` performs the
  tool call against the deterministic in-memory business system and returns
  the result dict; `snapshot()` returns the deterministic final state
  (`menu`, `stock`, `orders`, `payments`, `outbox`, `card_limit`). Execution
  failures raise `runtime.backend.ToolError(code, detail, retryable)`; the
  canonical lookup of a `ToolError` is `error.canonical()` =
  `"<code>:<detail>"`. Only infrastructure transients set `retryable=True`
  (code `GATEWAY_BUSY`). Failures never mutate state.
- `runtime.models.MockModel(transcript)` — `model.next(messages)` returns the
  next emission: a tool call `{"kind": "tool_call", "name": ..., "arguments":
  {...}}` or a final answer `{"kind": "final", "answer": "..."}`. The model is
  deterministic and only reacts to the **feedback messages** you append (see
  the protocol below); if you feed it a malformed or mistyped history it stops
  following the transcript and the run diverges.

The transcript JSON you drive with is

```json
{"session": "...", "max_steps": <int>, "user": "<prompt>",
 "initial_state": {...}, "transients": [...], "decisions": [...]}
```

Start the conversation as `messages = [{"role": "user", "content":
transcript["user"]}]`. Note the visible transcript lives in
`/app/transcripts/session_A.json`; the grader supplies fresh ones (see
Grading).

## The protocol you must implement (the part you write)

Your loop repeatedly:

```
for step in 1 .. max_steps:
    emission = model.next(messages)
    - if emission is a final answer: record it and stop ("completed")
    - else classify it as one of:
      1. malformed        -> feedback MF, never executed
      2. unknown tool     -> feedback U,  never executed
      3. schema-invalid   -> feedback SI, never executed
      4. non-idempotent duplicate -> feedback R  (replayed, never re-executed)
      5. executable call  -> feedback OK (see retry policy)
    append the feedback message to `messages`, store the step in the log
after max_steps emissions without a final answer: stop ("step_cap")
```

### Feedback messages (append `{"role": "tool", "content": ...}`)

One line, `<TYPE>:<payload>`:

| TYPE | when | payload | category |
|---|---|---|---|
| `EXECUTED` | a tool call executed (or executed-after-retries) | `json.dumps(result, sort_keys=True)` | K |
| `REPLAYED` | a duplicate of an already executed non-idempotent call | `json.dumps(cached_result, sort_keys=True)` | R |
| `MALFORMED` | malformed model output | one of `NOT_OBJECT`, `MISSING_NAME`, `INVALID_ARGUMENTS` | M |
| `SCHEMA_ERROR` | schema-invalid call | the canonical string from `ToolRegistry.validate` | S |
| `UNKNOWN_TOOL` | tool name not in the registry | the tool name | U |
| `EXEC_ERROR` | non-retryable execution failure | `EXEC_ERROR:<code>:<detail>` | E |

A malformed emission is one that is not a dict (`MALFORMED:NOT_OBJECT`), one
whose `name` is missing or not a non-empty string
(`MALFORMED:MISSING_NAME`), or one whose `arguments` is missing or not a JSON
object (`MALFORMED:INVALID_ARGUMENTS`). Check in that order, feed exactly
one error back per emission, and never execute a call that shares any of the
four failure categories.

### Schema validation

Call `registry.validate(name, args)` on every well-formed call before any
idempotency or execution logic. `None` means valid; otherwise the returned
string is both your log `error` field and the feedback content.

### Retry policy

A tool call whose execution raises `ToolError` with `retryable=True` is
retried **silently inside the same step** — no feedback message is appended
and no extra model turn happens — with exponential backoff
`RETRY_BASE_DELAY_SEC * 2^(attempt)` for up to `MAX_EXEC_RETRIES` total
attempts. Record the number of silently retried attempts in the step's
`retries` field. On success the feedback is a single `EXECUTED` message. A
non-retryable `ToolError` (or an exhausted retry budget) ends the step with
`outcome="error"` and feedback `EXEC_ERROR:<code>:<detail>`.

### Idempotency (non-idempotent tools must never run twice)

For a tool whose schema declares `"idempotent": false`, a call that is
byte-identical (same tool, same arguments, so same `json.dumps(args,
sort_keys=True)`) to a call that already executed **successfully** must not
execute again: return the previously produced result instead, with
`outcome="replayed"` and feedback `REPLAYED:<payload>`. Idempotent tools are
**always** (re)executed — never replayed — and never cached as "done".

### Step cap

The transcript has a `max_steps` field. Your loop must drive no more than
`max_steps` emissions total; if no final answer arrives in that budget it
must stop on its own, record `"terminated": "step_cap"` and still snapshot
the store state. A loop that runs forever, or that stops early for any other
reason, fails. A final answer arriving at exactly step `max_steps` is
processed normally and ends the run as `"completed"`.

### The run log (grade-able output)

Your loop writes a single JSON document to the output path argument:

```json
{
  "session": "<from transcript>",
  "terminated": "completed" | "step_cap",
  "steps": [ { "step": 1, "kind": "tool_call", "tool": "...",
               "arguments": {...}, "outcome": "executed",
               "error": null, "retries": 0, "result": {...} }, ... ],
  "final_state": { "menu": [...], "stock": {...}, "orders": [...],
                   "payments": [...], "outbox": [...], "card_limit": ... }
}
```

Step fields, exactly: `step` (1-based counter), `kind` (`tool_call` or
`final`), `tool` (tool name or `null`), `arguments` (the emission's
arguments or `null`), `outcome` (`executed` | `replayed` | `malformed` |
`schema_error` | `unknown_tool` | `error` | `final`), `error` (feedback string
mentioned or `null`), `retries` (int, number of silently retried attempts, 0
when none), `result` (executed/replayed result dict or `null`).  For
`outcome: "final"`, a `kind` is `final` and the additional `answer` string
is the model's final answer. `final_state` is exactly `store.snapshot()`.

## Deliverables

- `/app/agent_loop.py` — the executor loop (a complete, self-contained Python
  program; only stdlib + the `runtime` package; takes exactly two
  command-line arguments: `<transcript.json> <out.json>`)
- `/app/run_A.json` — the JSON log produced by executing it against
  `/app/transcripts/session_A.json` into `/app/run_A.json`:
  `python3 /app/agent_loop.py /app/transcripts/session_A.json /app/run_A.json`

## Grading

The grader executes your loop from a clean slate on the visible transcript and on at least two hidden transcripts it mounts under `/tests/hidden` (you must not read `/tests`), then compares each produced log with the expected
run of that transcript **literally** — the exact step sequence (tool,
arguments, outcome, retries per step), the exact error strings returned, the
exact final answer / termination reason, and the exact `final_state`
(numbers, orderings, keys). A single diverging error string, step order,
missing retry/replay, wrong snapshot, or dropped step is a failure. Design
against these failure modes: malformed or out-of-range calls, duplicates of
non-idempotent tools when the model repeats itself, transiently failing calls
needing the retry policy, unknown tools, and a model that runs past the step
budget. While developing, run your loop on the visible
transcript and inspect the log yourself: a correct run ends with a `final`
step and `"terminated": "completed"` for session_A, and every tool in
`/app/registry.json` behaves as its declaration says.

Do not modify `/app/runtime/**`, `/app/registry.json` or
`/app/transcripts/**`. Under `/app`, the only new files are the two
deliverables above.