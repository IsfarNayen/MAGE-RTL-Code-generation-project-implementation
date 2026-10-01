"""Central configuration for MAGE.

All settings live here so no other file reads environment variables directly.
"""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class Config:
    """Immutable settings object.

    These values could live in .env, but algorithm settings are kept here so they
    are versioned in git (.env is git-ignored). A test for this will be added later.
    """
    gemini_api_key: str
    gemini_model: str
    iverilog_path: Path
    vvp_path: Path

    # MAGE algorithm settings (values from the paper where given).
    num_candidates: int = 4        # c: RTL candidates sampled per problem
    top_k: int = 2                 # K: candidates kept for debugging
    high_temperature: float = 0.85 # T for candidate sampling (paper: 0.85)
    top_p: float = 0.95            # nucleus sampling (paper: 0.95)
    max_syntax_fixes: int = 5      # s: syntax-fix attempts (paper: 5)
    max_debug_rounds: int = 5      # iteration limit for debugging
    checkpoint_window: int = 5     # L_W: cycles of history shown to Debug Agent


def _require(name: str) -> str:
    """Return an environment variable, or fail early with a clear message."""
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required setting '{name}' in .env")
    return value


def load_config() -> Config:
    """Read .env and build a Config object."""
    load_dotenv()
    return Config(
        gemini_api_key=_require("GEMINI_API_KEY"),
        gemini_model=_require("GEMINI_MODEL"),
        iverilog_path=Path(_require("IVERILOG_PATH")),
        vvp_path=Path(_require("VVP_PATH")),
    )