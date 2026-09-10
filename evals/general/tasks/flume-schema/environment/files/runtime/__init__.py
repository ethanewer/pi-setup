"""flume-schema agent platform runtime.

The deterministic building blocks the executor loop is built on:

    runtime.protocol  canonical feedback strings and retry-policy constants
    runtime.registry  ToolRegistry: loads registry.json, validates calls and
                      emits canonical SCHEMA_ERROR strings
    runtime.backend   Store: the deterministic tool store; Store.execute()
                      raises ToolError for failures, ToolError.retryable marks
                      transient (retryable) failures
    runtime.models    MockModel: the deterministic scripted model
"""