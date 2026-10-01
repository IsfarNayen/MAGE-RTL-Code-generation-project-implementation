"""Runs Verilog through Icarus Verilog and reports how many checks passed."""

import os
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from mage.config import Config


@dataclass
class SimulationResult:
    """What we learned from one compile-and-simulate run."""
    
    compiled: bool  # did the Verilog compile?
    log: str  # compiler errors, or what the simulation printed
    total_checks: int = 0
    mismatches: int = 0
    score: float = 0.0  # 1 - mismatches / total_checks (paper Eq. 2)
    passed: bool = False



def run_simulation(config: Config, design_code: str, testbench_code: str) -> SimulationResult:
    """Compile the design + testbench, run it, and read the RESULT line it prints."""
    # iverilog needs its own folder on PATH so it can find its DLL files.
    env = os.environ.copy()
    env["PATH"] = str(config.iverilog_path.parent) + os.pathsep + env["PATH"]

    with tempfile.TemporaryDirectory() as tmp:
        design_file = Path(tmp) / "design.v"
        testbench_file = Path(tmp) / "tb.v"
        sim_file = Path(tmp) / "sim.vvp"
        design_file.write_text(design_code, encoding="utf-8")
        testbench_file.write_text(testbench_code, encoding="utf-8")

        # Step 1: compile.
        compile_run = subprocess.run(
            [str(config.iverilog_path), "-g2005", "-o", str(sim_file),
             str(design_file), str(testbench_file)],
            capture_output=True, text=True, env=env,
        )
        if compile_run.returncode != 0:
            return SimulationResult(compiled=False, log=compile_run.stdout + compile_run.stderr)

        # Step 2: run (with a time limit in case the design loops forever).
        try:
            sim_run = subprocess.run(
                [str(config.vvp_path), str(sim_file)],
                capture_output=True, text=True, timeout=30, env=env,
            )
        except subprocess.TimeoutExpired:
            return SimulationResult(compiled=True, log="Simulation timed out after 30 seconds")

    # Step 3: read the testbench's summary line.
    log = sim_run.stdout + sim_run.stderr
    match = re.search(r"RESULT total=(\d+) mismatches=(\d+)", log)
    if match is None:
        return SimulationResult(compiled=True, log=log)  # testbench never reported

    total = int(match.group(1))
    mismatches = int(match.group(2))
    return SimulationResult(
        compiled=True,
        log=log,
        total_checks=total,
        mismatches=mismatches,
        score=1 - mismatches / total if total else 0.0,
        passed=total > 0 and mismatches == 0,
    )