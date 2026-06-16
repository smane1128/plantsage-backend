"""
Care schedule interval resolver.

Determines fertilize / prune / repot / pest_check intervals (in days)
for a plant when it is added to My Garden.

Priority:
  1. Parse AI response details JSON (growing.fertilizer, maintenance.pruning, etc.)
  2. Fall back to plant_type rules if AI data is absent or unparseable.
"""
from __future__ import annotations

import json
import re

# ── Plant-type fallback table ─────────────────────────────────────────────────
_TYPE_DEFAULTS: dict[str, dict[str, int]] = {
    "succulent":  {"fertilize": 60,  "prune": 90,  "repot": 730, "pest_check": 30},
    "cactus":     {"fertilize": 60,  "prune": 90,  "repot": 730, "pest_check": 30},
    "flower":     {"fertilize": 14,  "prune": 30,  "repot": 365, "pest_check": 14},
    "shrub":      {"fertilize": 21,  "prune": 45,  "repot": 365, "pest_check": 21},
    "tree":       {"fertilize": 30,  "prune": 60,  "repot": 730, "pest_check": 21},
    "vegetable":  {"fertilize": 14,  "prune": 21,  "repot": 180, "pest_check": 7},
    "herb":       {"fertilize": 14,  "prune": 14,  "repot": 180, "pest_check": 14},
    "vine":       {"fertilize": 21,  "prune": 30,  "repot": 365, "pest_check": 14},
    "grass":      {"fertilize": 30,  "prune": 14,  "repot": 730, "pest_check": 21},
    "other":      {"fertilize": 30,  "prune": 60,  "repot": 365, "pest_check": 14},
}
_DEFAULT = _TYPE_DEFAULTS["other"]


def _text_to_days(text: str) -> int | None:
    """
    Convert a natural-language frequency string to days.
    Returns None if the text cannot be parsed.

    Examples:
        "Monthly balanced NPK"      → 30
        "Every 2 weeks"             → 14
        "Fortnightly"               → 14
        "Weekly"                    → 7
        "Twice a month"             → 14
        "Every 3 months"            → 90
        "Annual light pruning"      → 365
        "Every 6 months"            → 180
        "Daily"                     → 1
    """
    if not text:
        return None
    t = text.lower()

    # "twice a month" / "twice monthly"
    if re.search(r"twice.{0,10}month", t):
        return 14

    # "every X weeks"
    m = re.search(r"every\s+(\d+)\s+week", t)
    if m:
        return int(m.group(1)) * 7

    # "every X months"
    m = re.search(r"every\s+(\d+)\s+month", t)
    if m:
        return int(m.group(1)) * 30

    # "every X days"
    m = re.search(r"every\s+(\d+)\s+day", t)
    if m:
        return int(m.group(1))

    # named frequencies
    if re.search(r"\bdaily\b",         t): return 1
    if re.search(r"\bweekly\b",        t): return 7
    if re.search(r"\bfortnightly\b",   t): return 14
    if re.search(r"\bbiweekly\b",      t): return 14
    if re.search(r"\bmonthly\b",       t): return 30
    if re.search(r"\bquarterly\b",     t): return 90
    if re.search(r"\bbiannual\b",      t): return 180
    if re.search(r"\bsemi.annual\b",   t): return 180
    if re.search(r"\bannual\b|yearly\b", t): return 365

    # "once a month / week / year"
    m = re.search(r"once\s+a\s+(week|month|year)", t)
    if m:
        unit = m.group(1)
        return {"week": 7, "month": 30, "year": 365}[unit]

    return None


def _pest_check_from_susceptibility(text: str) -> int | None:
    """
    Map a pest_susceptibility string to a pest check interval.
    High → check every 7 days, Medium → 14, Low → 21.
    """
    if not text:
        return None
    t = text.lower()
    if "high" in t:   return 7
    if "medium" in t: return 14
    if "low" in t:    return 21
    return None


def get_care_intervals(
    details_json: str | None,
    plant_type: str | None,
) -> dict[str, int]:
    """
    Return a dict of {task_type: interval_days} for all 4 care tasks.

    Tries to extract intervals from the AI details JSON first;
    falls back to plant_type rules for any task where AI data is missing.
    """
    # Determine fallback row
    pt = (plant_type or "").lower().strip()
    fallback = _TYPE_DEFAULTS.get(pt, _DEFAULT)

    result: dict[str, int] = {}

    # ── Try to parse AI details ───────────────────────────────────────────────
    if details_json:
        try:
            data = json.loads(details_json)

            # Fertilize — from growing.fertilizer
            fertilizer_text = (
                data.get("growing", {}).get("fertilizer") or ""
            )
            days = _text_to_days(fertilizer_text)
            result["fertilize"] = days if days else fallback["fertilize"]

            # Prune — from maintenance.pruning
            pruning_text = (
                data.get("maintenance", {}).get("pruning") or ""
            )
            days = _text_to_days(pruning_text)
            result["prune"] = days if days else fallback["prune"]

            # Repot — no direct AI field; use plant_type rules
            result["repot"] = fallback["repot"]

            # Pest check — from maintenance.pest_susceptibility
            pest_text = (
                data.get("maintenance", {}).get("pest_susceptibility") or ""
            )
            days = _pest_check_from_susceptibility(pest_text)
            result["pest_check"] = days if days else fallback["pest_check"]

        except (json.JSONDecodeError, AttributeError):
            result = dict(fallback)
    else:
        result = dict(fallback)

    return result
