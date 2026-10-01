"""Demo: generate RTL for one problem and check it with the simulator."""

from pathlib import Path

from mage.agents.rtl_agent import RTLAgent
from mage.config import load_config
from mage.llm_client import LLMClient
from mage.tools.simulator import run_simulation

PROBLEM_DIR = Path("problems/counter")  # change this to run a different problem


def main() -> None:
    # 1. Read the problem files.
    spec = (PROBLEM_DIR / "spec.txt").read_text(encoding="utf-8")
    testbench = (PROBLEM_DIR / "tb.v").read_text(encoding="utf-8")

    # 2. Set up the settings and the agent.
    config = load_config()
    agent = RTLAgent(LLMClient(config))

    # 3. Ask Gemini to write the Verilog, and save it so you can open it.
    print("[1/3] Asking Gemini to write the Verilog...")
    rtl = agent.generate(spec)
    Path("outputs").mkdir(exist_ok=True)
    Path("outputs/counter.v").write_text(rtl, encoding="utf-8")

    # 4. Run the Verilog through the simulator.
    print("[2/3] Simulating against the testbench...")
    result = run_simulation(config, rtl, testbench)

    # 5. Show the results.
    print("[3/3] Report")
    print("-" * 40)
    print(f"Compiled   : {result.compiled}")
    print(f"Checks     : {result.total_checks}")
    print(f"Mismatches : {result.mismatches}")
    print(f"Score      : {result.score:.3f}")
    print(f"Result     : {'PASS' if result.passed else 'FAIL'}")
    print("-" * 40)
    if not result.passed:
        print("Simulator log:")
        print(result.log)


if __name__ == "__main__":
    main()