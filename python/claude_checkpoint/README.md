# Claude checkpoint mod (prototype)

A Claude Code mod that makes a Claude Agent SDK run durable by checkpointing every model step
and tool call in a Temporal workflow. When the activity retries, saved steps are replayed from
the workflow instead of calling the model or the tool again.

- `mod/hooks/register.ts` wraps `turn.step` and `tool.call`. Before each one it looks up a saved
  result; after each one it saves the result.
- `activities.py` runs Claude in an activity and exposes the workflow to the mod as the
  `temporal` MCP server (`lookup` is a query, `checkpoint` is an update).
- `workflow.py` stores checkpoints. The first write for an ID wins.

## Run

```sh
temporal server start-dev
export ANTHROPIC_API_KEY=...
uv run run.py
```

The example asks Claude to add numbers with an `add` tool. Each model step and tool call shows up
as a `checkpoint` update in the workflow history.
