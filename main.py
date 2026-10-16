"""Demo: sample several RTL designs, then let the Debug Agent repair the best one.

Usage:  python main.py seq_detector
"""

import sys
from pathlib import Path

from mage.agents.debug_agent import DebugAgent
from mage.agents.rtl_agent import RTLAgent
from mage.config import load_config
from mage.llm_client import LLMClient
from mage.sampling import sample_and_rank
from mage.tools.simulator import run_simulation


def report(label, result):
    """Print one summary line for a simulation result."""
    status = "PASS" if result.passed else "FAIL"
    print(f"[{label}] mismatches={result.mismatches}/{result.total_checks}  "
          f"score={result.score:.3f}  {status}")


def main() -> None:
    # 1. Pick the problem folder and read its files.
    name = sys.argv[1] if len(sys.argv) > 1 else "seq_detector"
    problem_dir = Path("problems") / name
    output_dir = Path("outputs") / name
    output_dir.mkdir(parents=True, exist_ok=True)
    spec = (problem_dir / "spec.txt").read_text(encoding="utf-8")
    testbench = (problem_dir / "tb.v").read_text(encoding="utf-8")

    # 2. Set up the settings and the two agents.
    config = load_config()
    llm = LLMClient(config)
    rtl_agent = RTLAgent(llm)
    debug_agent = DebugAgent(llm)

    # 3. Sample several designs; the list is sorted, so the first one is the best.
    print(f"Problem: {name}")
    best = sample_and_rank(config, rtl_agent, spec, testbench, output_dir)[0]
    rtl, result = best.rtl, best.result
    report("Initial", result)

    # 4. Repair loop: fix, re-simulate, keep the fix only if the score improves.
    for round_number in range(1, config.max_debug_rounds + 1):
        if result.passed:
            break
        fixed_rtl = debug_agent.fix(spec, rtl, result.log)
        fixed_result = run_simulation(config, fixed_rtl, testbench)
        report(f"Round {round_number}", fixed_result)
        if fixed_result.score > result.score:
            rtl, result = fixed_rtl, fixed_result

    # 5. Save the best design.
    (output_dir / "final.v").write_text(rtl, encoding="utf-8")
    report("Final", result)


if __name__ == "__main__":
    main()