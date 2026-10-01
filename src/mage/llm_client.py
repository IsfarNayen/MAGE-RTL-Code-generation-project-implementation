"""LLM client: the only module that talks to Gemini.

Temporary server errors (like 503 'high demand') are retried automatically.
"""

import time
from typing import Callable

from google import genai
from google.genai import errors, types

from mage.config import Config

# HTTP status codes that mean "try again later", not "your request is wrong".
RETRYABLE_CODES = (429, 500, 502, 503, 504)


class LLMClient:
    """Sends prompts to Gemini and returns the reply text."""
    
    def __init__(
        self,
        config: Config,
        client=None,
        sleep: Callable[[float], None] = time.sleep,
        max_attempts: int = 6,
    ) -> None:
        self._config = config
        self._client = client or genai.Client(api_key=config.gemini_api_key)
        self._sleep = sleep
        self._max_attempts = max_attempts

    def generate(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.0,
        top_p: float | None = None,
    ) -> str:
        """Return Gemini's reply to `prompt`."""
        gen_config = types.GenerateContentConfig(
            system_instruction=system_prompt,
            temperature=temperature,
            top_p=top_p,
        )
        for attempt in range(1, self._max_attempts + 1):
            try:
                response = self._client.models.generate_content(
                    model=self._config.gemini_model,
                    contents=prompt,
                    config=gen_config,
                )
                return response.text or ""
            except errors.APIError as err:
                last_attempt = attempt == self._max_attempts
                if err.code not in RETRYABLE_CODES or last_attempt:
                    raise
                self._sleep(min(2**attempt, 60))  # wait 2, 4, 8, 16, 32 seconds

        raise RuntimeError("unreachable")