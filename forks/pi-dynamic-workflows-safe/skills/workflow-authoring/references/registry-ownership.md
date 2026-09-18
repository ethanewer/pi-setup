# Registry ownership

## Subagent model

The user chooses one subagent model with `/workflow-model`, from their pinned models. The choice lives in `~/.pi/workflows/subagent-model.json` as `{ "model": "provider/modelId", "thinking": "high" }`. Without a saved choice, agents use the main session model.

Every agent in a run uses that choice, including helpers, nested workflows, and follow-up turns on a thread. Scripts cannot override it. Legacy model and tier selectors are ignored. An unavailable configured model fails the call rather than silently switching models.

## Agent types

The agent registry owns agent-type names and their instructions, tools, and isolation policy. Use `agentType` only when context supplies both its name and purpose. Do not infer an agent type from a role-like label. Model fields in agent definitions are ignored.
