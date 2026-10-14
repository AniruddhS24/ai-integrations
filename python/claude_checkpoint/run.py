"""Runs a worker and one AgentWorkflow against a local Temporal server."""

import asyncio
import uuid

from temporalio.client import Client
from temporalio.worker import Worker

from activities import run_claude
from workflow import AgentWorkflow

PROMPT = "Use the add tool to compute 2 + 3, then use the add tool again to add 10 to that result. Reply with the final number."


async def main():
    client = await Client.connect("localhost:7233")
    async with Worker(client, task_queue="claude-checkpoint", workflows=[AgentWorkflow], activities=[run_claude]):
        result = await client.execute_workflow(AgentWorkflow.run, PROMPT, id=f"agent-{uuid.uuid4().hex[:8]}", task_queue="claude-checkpoint")
        print(f"[workflow] result: {result}")


if __name__ == "__main__":
    asyncio.run(main())
