"""Smoke test: verify the environment is ready before building MAGE agents.

Checks three things:
  1. Required settings exist in .env
  2. Icarus Verilog can compile and simulate a tiny design
  3. The Gemini API key works
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from dotenv import load_dotenv

REQUIRED_VARS = ["GEMINI_API_KEY", "GEMINI_MODEL", "IVERILOG_PATH", "VVP_PATH"]

# A tiny Verilog design + testbench used only to prove the simulator works.
TEST_VERILOG = """
module and_gate(input a, input b, output y);
  assign y = a & b;
endmodule

module tb;
  reg a, b; wire y;
  and_gate dut(.a(a), .b(b), .y(y));
  initial begin
    a = 1; b = 1; #1;
    if (y === 1) $display("SIM_PASS"); else $display("SIM_FAIL");
    $finish;
  end
endmodule
"""


def check_env_vars() -> bool:
    """Confirm every required setting is present in .env."""
    missing = [name for name in REQUIRED_VARS if not os.getenv(name)]
    if missing:
        print(f"[FAIL] Missing in .env: {', '.join(missing)}")
        return False
    print("[ OK ] All .env settings found")
    return True


def check_simulator() -> bool:
    """Compile and run a tiny design with iverilog + vvp."""
    iverilog = os.getenv("IVERILOG_PATH")
    vvp = os.getenv("VVP_PATH")
    # iverilog's internal compiler (lib/ivl/ivl.exe) needs DLLs that live in
    # iverilog's bin folder. Put that folder first on PATH for the child process only.
    sim_env = os.environ.copy()
    sim_env["PATH"] = str(Path(iverilog).parent) + os.pathsep + sim_env["PATH"]

    # A temporary folder is deleted automatically when the 'with' block ends.
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "test.v"
        out = Path(tmp) / "test.vvp"
        src.write_text(TEST_VERILOG)

        try:
            compile_result = subprocess.run(
                [iverilog, "-o", str(out), str(src)],
                capture_output=True, text=True, timeout=30, env=sim_env,
            )
            if compile_result.returncode != 0:
                print(
                    f"[FAIL] iverilog compile error "
                    f"(exit code {compile_result.returncode}):\n"
                    f"  stdout: {compile_result.stdout.strip() or '(empty)'}\n"
                    f"  stderr: {compile_result.stderr.strip() or '(empty)'}"
                )
                return False

            sim_result = subprocess.run(
                [vvp, str(out)], capture_output=True, text=True, timeout=30, env=sim_env,
            )
        except FileNotFoundError as err:
            print(f"[FAIL] Simulator not found: {err}")
            return False

    if "SIM_PASS" in sim_result.stdout:
        print("[ OK ] Icarus Verilog compiles and simulates correctly")
        return True
    print(f"[FAIL] Unexpected simulation output:\n{sim_result.stdout}")
    return False


def check_llm() -> bool:
    """Send one short prompt to Gemini and confirm we get a reply."""
    from google import genai  # imported here so the other checks run even if this package is missing

    try:
        client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
        response = client.models.generate_content(
            model=os.getenv("GEMINI_MODEL"),
            contents="Reply with exactly the word: READY",
        )
    except Exception as err:  # broad on purpose: any failure here means "not ready"
        print(f"[FAIL] Gemini call failed: {err}")
        return False

    print(f"[ OK ] Gemini replied: {response.text.strip()!r}")
    return True


def main() -> int:
    load_dotenv()  # copies values from .env into os.environ

    if not check_env_vars():
        return 1  # no point running the others without settings

    results = [check_simulator(), check_llm()]
    if all(results):
        print("\nAll checks passed. Ready to build MAGE.")
        return 0
    print("\nSome checks failed. Fix the [FAIL] lines above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())