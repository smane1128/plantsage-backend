"""
Dynamic Malaysia nursery price estimator.

Price tiers are determined by plant category, rarity, and mature size.
A future `_MARKET_OVERRIDE` dict (or a `plant_market_prices` DB table) can
provide real market data that takes precedence over any generated price.
"""
from __future__ import annotations
import re

# ─── Future-ready market override ────────────────────────────────────────────
# Keyed by lower(scientific_name) or lower(plant_name).
# When a real plant_market_prices table is available, populate this from DB
# at startup and it will override all rule-based estimates.
_MARKET_OVERRIDE: dict[str, dict] = {}

# ─── Category keyword sets ────────────────────────────────────────────────────
_COMMON_ORNAMENTALS = {
    "jasmine", "jasminum", "hibiscus", "bougainvillea", "ixora",
    "marigold", "sunflower", "croton", "coleus", "impatiens",
    "vinca", "portulaca", "lantana", "ruellia", "pentas",
    "heliconia", "ginger lily", "plumbago", "duranta",
}

_FRUIT_TREES = {
    "lemon", "lime", "orange", "guava", "mango", "papaya",
    "banana", "pineapple", "starfruit", "carambola", "durian",
    "rambutan", "longan", "lychee", "mangosteen", "jackfruit",
    "ciku", "sapodilla", "manilkara", "psidium", "mangifera",
    "carica", "musa", "annona", "averrhoa",
}

_WATER_PLANTS = {
    "water lily", "nymphaea", "lotus", "nelumbo",
    "water hyacinth", "eichhornia", "water lettuce", "pistia",
    "water iris", "aquatic", "pond plant",
}

# ─── Base price ranges (RM lo, RM hi) per tier ───────────────────────────────
_RANGES: dict[str, dict[str, tuple[int, int]]] = {
    "common":  {"small": (8,  20),  "medium": (15,  50),  "large": (40,  120)},
    "fruit":   {"small": (20, 40),  "medium": (50,  120), "large": (120, 300)},
    "water":   {"small": (15, 30),  "medium": (30,  80),  "large": (80,  200)},
    "default": {"small": (10, 25),  "medium": (25,  70),  "large": (70,  180)},
}

_RARE_KEYWORDS = ("rare", "exotic", "uncommon", "endangered", "protected", "collectors")


def _classify(plant_name: str, scientific_name: str, plant_type: str) -> str:
    """Return one of: 'common', 'fruit', 'water', 'default'."""
    n = plant_name.lower()
    s = (scientific_name or "").lower()
    t = (plant_type or "").lower()

    for kw in _WATER_PLANTS:
        if kw in n or kw in s:
            return "water"

    for kw in _FRUIT_TREES:
        if kw in n or kw in s:
            return "fruit"
    if any(x in t for x in ("fruit", "vegetable", "herb")):
        return "fruit"

    for kw in _COMMON_ORNAMENTALS:
        if kw in n or kw in s:
            return "common"
    if any(x in t for x in ("ornamental", "flower", "shrub", "ground cover", "annual", "perennial")):
        return "common"

    return "default"


def _is_rare(plant_name: str, scientific_name: str, recommendation: str) -> bool:
    combined = f"{plant_name} {scientific_name or ''} {recommendation or ''}".lower()
    return any(kw in combined for kw in _RARE_KEYWORDS)


def _large_specimen(mature_height: str) -> bool:
    """True if mature height is ≥ 5 m."""
    m = re.search(r"(\d+(?:\.\d+)?)\s*m", (mature_height or "").lower())
    return m is not None and float(m.group(1)) >= 5


def _fmt(lo: int, hi: int) -> str:
    return f"RM{lo} - RM{hi}"


def generate_nursery_price(
    plant_name: str,
    scientific_name: str = "",
    plant_type: str = "",
    recommendation: str = "",
    mature_height: str = "",
) -> dict:
    """
    Generate a Malaysia nursery price estimate for one plant.

    Returns:
        {
            "small":  "RM8 - RM20",
            "medium": "RM15 - RM50",
            "large":  "RM40 - RM120",
            "confidence": "Estimated",
        }

    Priority:
        1. _MARKET_OVERRIDE (real market data hook — future-ready)
        2. Rule-based estimate (category + rarity + mature-size modifiers)
    """
    override_key = (scientific_name or plant_name).lower().strip()
    if override_key in _MARKET_OVERRIDE:
        return _MARKET_OVERRIDE[override_key]

    category = _classify(plant_name, scientific_name, plant_type)
    ranges = {k: list(v) for k, v in _RANGES[category].items()}  # mutable copy

    # Rarity modifier: all tiers +50 %
    if _is_rare(plant_name, scientific_name, recommendation):
        ranges = {k: [int(v[0] * 1.5), int(v[1] * 1.5)] for k, v in ranges.items()}

    # Large mature specimen: large tier +30 %
    if _large_specimen(mature_height):
        lo, hi = ranges["large"]
        ranges["large"] = [int(lo * 1.3), int(hi * 1.3)]

    return {
        "small":      _fmt(*ranges["small"]),
        "medium":     _fmt(*ranges["medium"]),
        "large":      _fmt(*ranges["large"]),
        "confidence": "Estimated",
    }
