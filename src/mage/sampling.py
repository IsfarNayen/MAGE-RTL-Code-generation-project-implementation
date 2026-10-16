"""High-temperature RTL sampling and ranking (MAGE step 4).

Ask the RTL Agent for several different designs at a high temperature, simulate each
one, score it, and keep only the best few. Running several "dice rolls" makes it far
more likely that at least one design is (nearly) correct.
"""

from dataclasses import dataclass
from pathlib import Path

from mage.agents.rtl_agent import RTLAgent
from mage.config import Config
from mage.tools.simulator import SimulationResult, run_simulation


@dataclass
class Candidate:
    """One RTL design together with the result of simulating it."""

    rtl: str
    result: SimulationResult


def sample_and_rank(
    config: Config,
    rtl_agent: RTLAgent,
    spec: str,
    testbench: str,
    output_dir: Path | None = None,
) -> list[Candidate]:
    """Return the best `config.top_k` candidates, highest score first.

    If `output_dir` is given, every sampled design is saved there as 1.v, 2.v, 3.v, ...
    """
    candidates: list[Candidate] = []
    for number in range(1, config.num_candidates + 1):
        rtl = rtl_agent.generate(
            spec, temperature=config.high_temperature, top_p=config.top_p
        )
        if output_dir is not None:
            (output_dir / f"{number}.v").write_text(rtl, encoding="utf-8")
        result = run_simulation(config, rtl, testbench)
        print(f"  Candidate {number}/{config.num_candidates}: score={result.score:.3f}")
        candidates.append(Candidate(rtl, result))
        # if result.passed:  # a perfect design needs no more samples
        #     break

    candidates.sort(key=lambda c: c.result.score, reverse=True)
    return candidates[: config.top_k]
