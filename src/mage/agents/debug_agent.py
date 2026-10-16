"""Debug Agent: repairs a failing Verilog design using the specification and the simulator log."""

from mage.agents.rtl_agent import extract_verilog
from mage.llm_client import LLMClient

SYSTEM_PROMPT = """You are an expert RTL debugging engineer.
You are given a specification, a Verilog design that fails its testbench, and the simulator log.
Find the cause of the mismatches and return the corrected, complete module.
Rules:
- Keep the exact module name and port names from the specification.
- Use plain Verilog-2001 style (reg/wire, always @(...)); avoid SystemVerilog-only features.
- Reply with ONE ```verilog code block containing the full corrected module, and no explanation."""

MAX_LOG_LINES = 20  # the earliest mismatches are the most useful, so keep only the start


class DebugAgent:
    """Repairs a failing Verilog design using the simulator log and the specification."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    def fix(self, spec: str, rtl: str, log: str) -> str:
        """Return a corrected version of `rtl`."""
        short_log = "\n".join(log.splitlines()[:MAX_LOG_LINES])
        prompt = (
            f"Specification:\n{spec}\n\n"
            f"Current design:\n```verilog\n{rtl}\n```\n\n"
            f"Simulator log:\n{short_log}"
        )
        reply = self._llm.generate(prompt=prompt, system_prompt=SYSTEM_PROMPT, temperature=0.0)
        return extract_verilog(reply)
