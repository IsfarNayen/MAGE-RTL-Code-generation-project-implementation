"""RTL Agent: turns a natural-language specification into Verilog code."""

import re

from mage.llm_client import LLMClient

SYSTEM_PROMPT = """You are an expert RTL design engineer.
Write synthesizable Verilog that implements the given specification exactly.
Rules:
- Use plain Verilog-2001 style (reg/wire, always @(...)); avoid SystemVerilog-only features.
- Use exactly the module name and port names given in the specification.
- Reply with ONE ```verilog code block containing only the module, and no explanation."""

CODE_BLOCK = re.compile(r"```(?:verilog|systemverilog|v)?[ \t]*\n(.*?)```", re.DOTALL | re.IGNORECASE)


def extract_verilog(reply: str) -> str:
    """Pull the code out of a markdown code block; if there is none, use the whole reply."""
    match = CODE_BLOCK.search(reply)
    return (match.group(1) if match else reply).strip()


class RTLAgent:
    """Generates Verilog from a specification using the LLM."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    def generate(self, spec: str, temperature: float = 0.0, top_p: float | None = None) -> str:
        """Return Verilog source for `spec`."""
        reply = self._llm.generate(
            prompt=f"Specification:\n{spec}",
            system_prompt=SYSTEM_PROMPT,
            temperature=temperature,
            top_p=top_p,
        )
        return extract_verilog(reply)