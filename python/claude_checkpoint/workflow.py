from datetime import timedelta
from typing import Any

from temporalio import workflow

with workflow.unsafe.imports_passed_through():
    from activities import run_claude


@workflow.defn
class AgentWorkflow:
    def __init__(self):
        self.checkpoints: dict[str, Any] = {}

    @workflow.run
    async def run(self, prompt: str) -> str:
        result = await workflow.execute_activity(run_claude, prompt, start_to_close_timeout=timedelta(minutes=10))
        await workflow.wait_condition(workflow.all_handlers_finished)
        return result

    @workflow.update
    def checkpoint(self, req: dict) -> Any:
        # first write wins; a retry gets the stored value back
        return self.checkpoints.setdefault(req["id"], req["value"])

    @workflow.query
    def lookup(self, id: str) -> Any | None:
        return self.checkpoints.get(id)
