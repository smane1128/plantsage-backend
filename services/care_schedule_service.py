"""
Care schedule interval resolver — v3

Calendar tasks: fertilize | prune | pest_check  (repot removed — condition-based, not date-based)
Watering:       handled separately via get_watering_interval()

Priority for care tasks:
  1. Species-specific override  → source: "species_specific"
  2. AI response details JSON   → source: "ai_estimated"
  3. Plant-type fallback rules  → source: "plant_type_rule"

Lifespan guard:
  Tasks whose interval >= 90% of plant expected lifespan are dropped (None).
  Prune/fertilize are also skipped for plants where they are not applicable.

Returns
-------
get_care_intervals() → dict[str, dict | None]
  Keys: "fertilize", "prune", "pest_check"
  dict value  → {"interval_days": int, "source": str}  — create this task
  None value  → skip this task (not applicable / plant too short-lived)

get_watering_interval() → int
  Returns interval_days for watering. Always returns a value (minimum 1).
"""
from __future__ import annotations

import json
import re
from typing import Any

SOURCE_SPECIES = "species_specific"
SOURCE_AI      = "ai_estimated"
SOURCE_TYPE    = "plant_type_rule"

# repot intentionally excluded — it is condition-based, not calendar-based
_ALL_TASKS = ("fertilize", "prune", "pest_check")

# ── Species-specific overrides ────────────────────────────────────────────────
# "lifespan_days": approximate days until plant dies/is harvested (None = perennial)
# "watering_days": default watering interval in days
# "tasks": task_type → interval_days  (absent key = task not applicable for this plant)
_SPECIES_DATA: list[dict[str, Any]] = [

    # ── Annuals / short crops ────────────────────────────────────────────────
    {
        "scientific": ["helianthus annuus"],
        "common":     ["sunflower"],
        "lifespan_days": 90,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "pest_check": 14},
        # prune: not applicable for sunflowers
    },
    {
        "scientific": ["lactuca sativa"],
        "common":     ["lettuce", "selada"],
        "lifespan_days": 75,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["zinnia elegans", "zinnia"],
        "common":     ["zinnia"],
        "lifespan_days": 70,
        "watering_days": 3,
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["tagetes erecta", "tagetes patula", "tagetes"],
        "common":     ["marigold"],
        "lifespan_days": 90,
        "watering_days": 3,
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
        # prune = dead-heading only
    },
    {
        "scientific": ["cosmos bipinnatus", "cosmos sulphureus"],
        "common":     ["cosmos"],
        "lifespan_days": 90,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["brassica rapa subsp. chinensis", "brassica rapa"],
        "common":     ["pak choi", "bok choy", "pok choy", "sawi"],
        "lifespan_days": 60,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["ipomoea aquatica"],
        "common":     ["kangkung", "water spinach", "morning glory vegetable"],
        "lifespan_days": 45,
        "watering_days": 1,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["amaranthus tricolor", "amaranthus viridis", "amaranthus"],
        "common":     ["bayam", "amaranth"],
        "lifespan_days": 45,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["cucumis sativus"],
        "common":     ["cucumber", "timun"],
        "lifespan_days": 75,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["raphanus sativus"],
        "common":     ["radish", "lobak"],
        "lifespan_days": 30,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "pest_check": 14},
    },
    {
        "scientific": ["coriandrum sativum"],
        "common":     ["coriander", "cilantro", "daun ketumbar"],
        "lifespan_days": 90,
        "watering_days": 2,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["allium fistulosum", "allium schoenoprasum"],
        "common":     ["spring onion", "scallion", "chives", "daun bawang"],
        "lifespan_days": 90,
        "watering_days": 2,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },

    # ── Short perennials / grown as annuals ──────────────────────────────────
    {
        "scientific": ["solanum lycopersicum"],
        "common":     ["tomato", "tomatoes", "tomat"],
        "lifespan_days": 150,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
    },
    {
        "scientific": ["capsicum annuum", "capsicum frutescens"],
        "common":     ["chili", "chilli", "pepper", "cili"],
        "lifespan_days": 365,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "prune": 60, "pest_check": 14},
    },
    {
        "scientific": ["ocimum basilicum"],
        "common":     ["basil", "sweet basil", "daun selasih"],
        "lifespan_days": 180,
        "watering_days": 2,
        "tasks": {"fertilize": 14, "prune": 14, "pest_check": 14},
    },
    {
        "scientific": ["petroselinum crispum"],
        "common":     ["parsley"],
        "lifespan_days": 365,
        "watering_days": 2,
        "tasks": {"fertilize": 21, "prune": 14, "pest_check": 21},
    },

    # ── Long-lived perennials / shrubs ───────────────────────────────────────
    {
        "scientific": ["rosa"],
        "common":     ["rose", "mawar"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "prune": 30, "pest_check": 7},
    },
    {
        "scientific": ["hibiscus rosa-sinensis", "hibiscus"],
        "common":     ["hibiscus", "bunga raya", "rosemallow"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "prune": 45, "pest_check": 14},
    },
    {
        "scientific": ["bougainvillea glabra", "bougainvillea spectabilis", "bougainvillea"],
        "common":     ["bougainvillea", "bunga kertas"],
        "lifespan_days": None,
        "watering_days": 4,
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },
    {
        "scientific": ["plumeria rubra", "plumeria obtusa", "plumeria"],
        "common":     ["frangipani", "plumeria", "kamboja"],
        "lifespan_days": None,
        "watering_days": 5,
        "tasks": {"fertilize": 30, "prune": 365, "pest_check": 21},
    },
    {
        "scientific": ["ixora coccinea", "ixora"],
        "common":     ["ixora", "jungle geranium", "bunga jejarum"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },
    {
        "scientific": ["murraya koenigii"],
        "common":     ["curry leaf", "daun kari"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["mentha"],
        "common":     ["mint", "daun pudina"],
        "lifespan_days": None,
        "watering_days": 2,
        "tasks": {"fertilize": 21, "prune": 14, "pest_check": 14},
    },
    {
        "scientific": ["pandanus amaryllifolius"],
        "common":     ["pandan", "screwpine", "daun pandan"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },

    # ── Succulents ───────────────────────────────────────────────────────────
    {
        "scientific": ["aloe vera", "aloe barbadensis"],
        "common":     ["aloe vera", "aloe"],
        "lifespan_days": None,
        "watering_days": 14,
        "tasks": {"fertilize": 60, "pest_check": 30},
        # prune: not applicable
    },
    {
        "scientific": ["echeveria"],
        "common":     ["echeveria"],
        "lifespan_days": None,
        "watering_days": 14,
        "tasks": {"fertilize": 60, "pest_check": 30},
    },

    # ── Tropical foliage ─────────────────────────────────────────────────────
    {
        "scientific": ["epipremnum aureum"],
        "common":     ["pothos", "money plant", "devil's ivy"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 30, "prune": 30, "pest_check": 14},
    },
    {
        "scientific": ["sansevieria trifasciata", "dracaena trifasciata"],
        "common":     ["snake plant", "mother-in-law's tongue", "lidah mertua"],
        "lifespan_days": None,
        "watering_days": 14,
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        "scientific": ["spathiphyllum wallisii", "spathiphyllum"],
        "common":     ["peace lily"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 14},
    },
    {
        "scientific": ["monstera deliciosa", "monstera"],
        "common":     ["monstera", "swiss cheese plant"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 14},
    },
    {
        "scientific": ["ficus benjamina", "ficus lyrata", "ficus elastica"],
        "common":     ["ficus", "rubber plant", "fiddle leaf fig", "weeping fig"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["caladium bicolor", "caladium"],
        "common":     ["caladium", "keladi"],
        "lifespan_days": None,
        "watering_days": 4,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["aglaonema"],
        "common":     ["aglaonema", "chinese evergreen"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },

    # ── Orchids ──────────────────────────────────────────────────────────────
    {
        "scientific": ["dendrobium", "phalaenopsis", "vanda", "oncidium", "cattleya",
                       "dendrobium phalaenopsis", "dendrobium hybrid"],
        "common":     ["orchid", "dendrobium", "moth orchid", "vanda orchid",
                       "dancing lady orchid", "anggrek"],
        "lifespan_days": None,
        "watering_days": 7,
        "tasks": {"fertilize": 14, "pest_check": 21},
        # prune: not applicable — remove spent flower spikes only when brown
    },

    # ── Flowering shrubs (gaps) ───────────────────────────────────────────────
    {
        "scientific": ["gardenia jasminoides", "gardenia augusta", "gardenia"],
        "common":     ["gardenia", "cape jasmine"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "prune": 60, "pest_check": 14},
    },

    # ── Tropical fruits & edibles ─────────────────────────────────────────────
    {
        "scientific": ["musa paradisiaca", "musa acuminata", "musa balbisiana", "musa"],
        "common":     ["banana", "pisang", "banana tree"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "pest_check": 14},
        # prune: remove dead/yellowed leaves and spent suckers as needed
    },
    {
        "scientific": ["mangifera indica"],
        "common":     ["mango", "mangga"],
        "lifespan_days": None,
        "watering_days": 5,
        "tasks": {"fertilize": 30, "prune": 365, "pest_check": 21},
    },
    {
        "scientific": ["carica papaya"],
        "common":     ["papaya", "betik", "papaw"],
        "lifespan_days": 730,
        "watering_days": 3,
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["psidium guajava"],
        "common":     ["guava", "jambu batu", "jambu"],
        "lifespan_days": None,
        "watering_days": 4,
        "tasks": {"fertilize": 30, "prune": 90, "pest_check": 21},
    },
    {
        "scientific": ["averrhoa carambola"],
        "common":     ["starfruit", "star fruit", "belimbing"],
        "lifespan_days": None,
        "watering_days": 4,
        "tasks": {"fertilize": 30, "prune": 180, "pest_check": 21},
    },
    {
        "scientific": ["ananas comosus"],
        "common":     ["pineapple", "nanas"],
        "lifespan_days": 730,
        "watering_days": 5,
        "tasks": {"fertilize": 30, "pest_check": 21},
    },

    # ── Ginger family ─────────────────────────────────────────────────────────
    {
        "scientific": ["zingiber officinale"],
        "common":     ["ginger", "halia"],
        "lifespan_days": 365,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "pest_check": 30},
    },
    {
        "scientific": ["curcuma longa"],
        "common":     ["turmeric", "kunyit"],
        "lifespan_days": 365,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "pest_check": 30},
    },
    {
        "scientific": ["etlingera elatior"],
        "common":     ["torch ginger", "bunga kantan"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["alpinia purpurata", "alpinia galanga"],
        "common":     ["red ginger", "galangal", "lengkuas"],
        "lifespan_days": None,
        "watering_days": 3,
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },

    # ── Palms ─────────────────────────────────────────────────────────────────
    {
        "scientific": ["chrysalidocarpus lutescens", "dypsis lutescens",
                       "areca catechu", "cocos nucifera", "livistona chinensis",
                       "roystonea regia", "wodyetia bifurcata"],
        "common":     ["areca palm", "golden cane palm", "coconut palm", "coconut",
                       "fan palm", "foxtail palm", "kelapa", "pinang"],
        "lifespan_days": None,
        "watering_days": 4,
        "tasks": {"fertilize": 60, "pest_check": 30},
        # prune: remove dead fronds only when fully brown
    },
]

# Build O(1) lookup dicts
_BY_SCIENTIFIC: dict[str, dict] = {}
_BY_COMMON:     dict[str, dict] = {}
for _entry in _SPECIES_DATA:
    for _name in _entry["scientific"]:
        _BY_SCIENTIFIC[_name.lower()] = _entry
    for _name in _entry["common"]:
        _BY_COMMON[_name.lower()] = _entry


def _lookup_species(scientific_name: str | None, common_name: str | None) -> dict | None:
    """Return species override entry if found, else None."""
    if scientific_name:
        s = scientific_name.lower().strip()
        if s in _BY_SCIENTIFIC:
            return _BY_SCIENTIFIC[s]
        # partial match: "Rosa hybrida" → "rosa"
        for key, entry in _BY_SCIENTIFIC.items():
            if s.startswith(key) or key.startswith(s.split()[0]):
                return entry
    if common_name:
        c = common_name.lower().strip()
        if c in _BY_COMMON:
            return _BY_COMMON[c]
        for key, entry in _BY_COMMON.items():
            if key in c:
                return entry
    return None


# ── Plant-type fallback tables ────────────────────────────────────────────────
_TYPE_DEFAULTS: dict[str, dict[str, int]] = {
    "succulent":  {"fertilize": 60,  "prune": 90,  "pest_check": 30},
    "cactus":     {"fertilize": 60,  "prune": 90,  "pest_check": 30},
    "flower":     {"fertilize": 14,  "prune": 30,  "pest_check": 14},
    "shrub":      {"fertilize": 21,  "prune": 45,  "pest_check": 21},
    "tree":       {"fertilize": 30,  "prune": 60,  "pest_check": 21},
    "vegetable":  {"fertilize": 14,  "prune": 21,  "pest_check": 7},
    "herb":       {"fertilize": 14,  "prune": 14,  "pest_check": 14},
    "vine":       {"fertilize": 21,  "prune": 30,  "pest_check": 14},
    "grass":      {"fertilize": 30,  "prune": 14,  "pest_check": 21},
    "other":      {"fertilize": 30,  "prune": 60,  "pest_check": 14},
}
_DEFAULT = _TYPE_DEFAULTS["other"]

_WATERING_DEFAULTS: dict[str, int] = {
    "succulent":  14,
    "cactus":     21,
    "flower":     3,
    "shrub":      4,
    "tree":       5,
    "vegetable":  2,
    "herb":       2,
    "vine":       3,
    "grass":      3,
    "other":      4,
}
_WATERING_DEFAULT = _WATERING_DEFAULTS["other"]


def _text_to_days(text: str) -> int | None:
    """Convert natural-language frequency to days. Returns None if unparseable."""
    if not text:
        return None
    t = text.lower()

    if re.search(r"twice.{0,10}month", t): return 14

    m = re.search(r"every\s+(\d+)\s+week", t)
    if m: return int(m.group(1)) * 7

    m = re.search(r"every\s+(\d+)\s+month", t)
    if m: return int(m.group(1)) * 30

    m = re.search(r"every\s+(\d+)\s+day", t)
    if m: return int(m.group(1))

    if re.search(r"\bdaily\b",           t): return 1
    if re.search(r"\bweekly\b",          t): return 7
    if re.search(r"\bfortnightly\b",     t): return 14
    if re.search(r"\bbiweekly\b",        t): return 14
    if re.search(r"\bmonthly\b",         t): return 30
    if re.search(r"\bquarterly\b",       t): return 90
    if re.search(r"\bbiannual\b",        t): return 180
    if re.search(r"\bsemi.annual\b",     t): return 180
    if re.search(r"\bannual\b|yearly\b", t): return 365

    m = re.search(r"once\s+a\s+(week|month|year)", t)
    if m:
        return {"week": 7, "month": 30, "year": 365}[m.group(1)]

    return None


def _pest_check_days(text: str) -> int | None:
    """Map pest_susceptibility text to check interval days."""
    if not text:
        return None
    t = text.lower()
    if "high"   in t: return 7
    if "medium" in t: return 14
    if "low"    in t: return 21
    return None


# ── Public API ────────────────────────────────────────────────────────────────

def get_care_intervals(
    details_json:    str | None,
    plant_type:      str | None,
    plant_name:      str | None = None,
    scientific_name: str | None = None,
) -> dict[str, dict[str, Any] | None]:
    """
    Return care schedule for fertilize, prune, pest_check.
    (repot is excluded — it is condition-based, not calendar-based)

    Each value is either:
      {"interval_days": int, "source": str}  — create this task
      None                                   — skip (not applicable / lifespan too short)
    """
    result: dict[str, dict[str, Any] | None] = {}

    # ── 1. Species-specific override ──────────────────────────────────────────
    species = _lookup_species(scientific_name, plant_name)
    if species:
        lifespan: int | None = species.get("lifespan_days")
        spec_tasks: dict[str, int] = species["tasks"]
        for task_type in _ALL_TASKS:
            if task_type not in spec_tasks:
                result[task_type] = None          # explicitly not applicable
            else:
                interval = spec_tasks[task_type]
                # Lifespan guard: skip if task would never realistically occur
                if lifespan and interval >= lifespan * 0.9:
                    result[task_type] = None
                else:
                    result[task_type] = {"interval_days": interval, "source": SOURCE_SPECIES}
        return result

    # ── 2. AI JSON + plant-type fallback ─────────────────────────────────────
    pt       = (plant_type or "").lower().strip()
    fallback = _TYPE_DEFAULTS.get(pt, _DEFAULT)

    # Rough lifespan cap for known short-lived types
    type_lifespan: int | None = None
    if pt == "vegetable":
        type_lifespan = 120

    ai_intervals: dict[str, int | None] = {}
    if details_json:
        try:
            data = json.loads(details_json)
            fertilizer_text = data.get("growing", {}).get("fertilizer") or ""
            pruning_text    = data.get("maintenance", {}).get("pruning") or ""
            pest_text       = data.get("maintenance", {}).get("pest_susceptibility") or ""

            ai_intervals["fertilize"]  = _text_to_days(fertilizer_text)
            ai_intervals["prune"]      = _text_to_days(pruning_text)
            ai_intervals["pest_check"] = _pest_check_days(pest_text)
        except (json.JSONDecodeError, AttributeError):
            pass

    for task_type in _ALL_TASKS:
        ai_val = ai_intervals.get(task_type)
        if ai_val is not None:
            interval = ai_val
            source   = SOURCE_AI
        else:
            interval = fallback[task_type]
            source   = SOURCE_TYPE

        if type_lifespan and interval >= type_lifespan * 0.9:
            result[task_type] = None
        else:
            result[task_type] = {"interval_days": interval, "source": source}

    return result


def get_watering_interval(
    details_json:    str | None,
    plant_type:      str | None,
    plant_name:      str | None = None,
    scientific_name: str | None = None,
) -> int:
    """
    Return watering interval in days. Always returns a positive integer.

    Priority:
      1. Species-specific database
      2. AI watering text from details_json
      3. Plant-type fallback
    """
    # 1. Species override
    species = _lookup_species(scientific_name, plant_name)
    if species and "watering_days" in species:
        return max(1, species["watering_days"])

    # 2. AI watering text
    if details_json:
        try:
            data = json.loads(details_json)
            watering_text = (
                data.get("growing", {}).get("watering") or
                data.get("growing", {}).get("water") or ""
            )
            days = _text_to_days(watering_text)
            if days and 1 <= days <= 30:
                return days
        except (json.JSONDecodeError, AttributeError):
            pass

    # 3. Plant-type fallback
    pt = (plant_type or "").lower().strip()
    return _WATERING_DEFAULTS.get(pt, _WATERING_DEFAULT)
