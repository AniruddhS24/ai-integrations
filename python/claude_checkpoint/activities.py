import json
from pathlib import Path

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query
from mcp.server import Server
from mcp.types import CallToolResult, ListToolsResult, TextContent, Tool
from temporalio import activity

MOD = Path(__file__).parent / "mod"

ADD = Tool(
    name="add",
    description="Add two numbers",
    inputSchema={"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}, "required": ["a", "b"]},
)


def text_result(value):
    return CallToolResult(content=[TextContent(type="text", text=value)])


def tools_server():
    """The example tool Claude can call."""

    async def on_list_tools(ctx, params):
        return ListToolsResult(tools=[ADD])

    async def on_call_tool(ctx, params):
        args = params.arguments
        print(f"[tool] add {args}", flush=True)
        return text_result(str(args["a"] + args["b"]))

    return {"type": "sdk", "name": "tools", "instance": Server("tools", version="1.0.0", on_list_tools=on_list_tools, on_call_tool=on_call_tool)}


def temporal_server(handle):
    """The bridge the mod reaches with $.mcp.call('temporal', ...)."""

    async def on_list_tools(ctx, params):
        return ListToolsResult(tools=[
            Tool(name="lookup", description="Internal.", inputSchema={"type": "object"}),
            Tool(name="checkpoint", description="Internal.", inputSchema={"type": "object"}),
        ])

    async def on_call_tool(ctx, params):
        args = params.arguments
        if params.name == "lookup":
            value = await handle.query("lookup", args["id"])
        else:
            value = await handle.execute_update("checkpoint", args, id=args["id"])
        return text_result(json.dumps(value))

    return {"type": "sdk", "name": "temporal", "instance": Server("temporal", version="1.0.0", on_list_tools=on_list_tools, on_call_tool=on_call_tool)}


@activity.defn
async def run_claude(prompt: str) -> str:
    handle = activity.client().get_workflow_handle(activity.info().workflow_id)
    options = ClaudeAgentOptions(
        tools=[],
        allowed_tools=["mcp__tools__add", "mcp__temporal__lookup", "mcp__temporal__checkpoint"],
        mcp_servers={"tools": tools_server(), "temporal": temporal_server(handle)},
        plugins=[{"type": "local", "path": str(MOD)}],
        setting_sources=[],
        system_prompt="You are a calculator agent. Only use the add tool for arithmetic.",
        model="claude-sonnet-5-5",
        max_turns=10,
    )
    async for msg in query(prompt=prompt, options=options):
        if isinstance(msg, ResultMessage):
            return msg.result
