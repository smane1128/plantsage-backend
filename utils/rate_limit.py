"""Simple in-memory sliding-window rate limiter for AI endpoints."""
from collections import deque
from datetime import datetime, timedelta
from fastapi import HTTPException

# ── Configuration ──────────────────────────────────────────────────────────────
_AI_WINDOW_SECS = 60   # rolling window in seconds
_AI_MAX_CALLS   = 20   # max AI requests per window (global, not per-IP)

_ai_timestamps: deque = deque()


def check_ai_rate_limit() -> None:
    """Raise HTTP 429 if the global AI call rate has been exceeded.

    This is a global guard (not per-IP) which is appropriate for a
    local app where all traffic originates from the same device.
    """
    now = datetime.utcnow()
    cutoff = now - timedelta(seconds=_AI_WINDOW_SECS)

    # Drop stale timestamps outside the current window
    while _ai_timestamps and _ai_timestamps[0] < cutoff:
        _ai_timestamps.popleft()

    if len(_ai_timestamps) >= _AI_MAX_CALLS:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Rate limit exceeded: max {_AI_MAX_CALLS} AI requests "
                f"per {_AI_WINDOW_SECS} seconds. Please wait a moment."
            ),
        )

    _ai_timestamps.append(now)
