"""runtime.protocol — canonical strings for the flume-schema typed-feedback protocol.

Every message the executor loop feeds back to the model is one line:

    <TYPE>:<payload>

TYPE is one of the constants below.  The mock model classifies a message by
its TYPE token only (the part before the first ':').  The run log's "error"
field holds the full feedback string for every non-success outcome; the
"result" field holds the parsed result object for executed/replayed outcomes.

The retry policy constants are also defined here; the executor loop must read
them from this module rather than redefining them.
"""

# feedback message type tokens (also the leading token of every error string)
EXECUTED = "EXECUTED"          # EXECUTED:<json result>   -> category letter K
REPLAYED = "REPLAYED"          # REPLAYED:<json result>   -> category letter R
MALFORMED = "MALFORMED"        # MALFORMED:<reason>       -> category letter M
SCHEMA_ERROR = "SCHEMA_ERROR"  # SCHEMA_ERROR:<detail>    -> category letter S
UNKNOWN_TOOL = "UNKNOWN_TOOL"  # UNKNOWN_TOOL:<name>      -> category letter U
EXEC_ERROR = "EXEC_ERROR"      # EXEC_ERROR:<code>:<detail> -> category letter E

# retry policy: a tool execution that raises a retryable ToolError is retried
# silently (no feedback message, no extra model turn) for up to MAX_EXEC_RETRIES
# extra attempts with exponential backoff RETRY_BASE_DELAY_SEC * 2**(attempt-1)
# between attempts.  Non-retryable errors are returned to the model immediately.
MAX_EXEC_RETRIES = 3
RETRY_BASE_DELAY_SEC = 0.05