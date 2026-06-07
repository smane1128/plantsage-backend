"""
Cultivation category classifier for Malaysian plant scanner.

Determines how realistically a plant can be cultivated by an average
Malaysian home gardener. Used to apply realistic business rules to the
recommendation engine output.

Categories
----------
common_garden    – Widely available at Malaysian nurseries; easy to grow at home
specialty_garden – Available at specialist nurseries; requires some expertise
advanced_collector – Rare or technically demanding; not beginner-friendly
botanical_only   – Cannot realistically be purchased or home-cultivated;
                   found only in botanical gardens, forest reserves,
                   or scientific/conservation programs
"""
from __future__ import annotations

# ── Botanical-only ────────────────────────────────────────────────────────────
# These plants are parasitic, critically endangered, require institutional
# host-plant setups, or are legally protected and never sold in nurseries.

_BOTANICAL_ONLY_GENERA: set[str] = {
    "rafflesia",       # obligate endoparasite on Tetrastigma vines; no roots/stems
    "amorphophallus",  # includes A. titanum (corpse flower); massive corm, specialist care
    "victoria",        # Victoria amazonica / cruziana; needs huge heated ponds
    "welwitschia",     # Namib Desert relic; impossible outside native climate
    "encephalartos",   # CITES-listed cycads; trade highly restricted
    "wollemia",        # Wollemi pine; critically endangered; highly restricted
    "rhizanthes",      # another parasitic genus related to Rafflesia
    "sapria",          # SE Asian endoparasite; near-impossible to cultivate
}

_BOTANICAL_ONLY_SPECIES: set[str] = {
    "rafflesia arnoldii",
    "rafflesia hasseltii",
    "rafflesia keithii",
    "rafflesia pricei",
    "rafflesia cantleyi",
    "amorphophallus titanum",
    "victoria amazonica",
    "victoria cruziana",
    "welwitschia mirabilis",
}

_BOTANICAL_ONLY_COMMON_NAMES: set[str] = {
    "rafflesia",
    "corpse flower",            # Amorphophallus titanum (different from Rafflesia)
    "giant water lily",
    "victoria water lily",
    "welwitschia",
    "corpse lily",              # common name for Rafflesia
}

# Keywords in description / plant name that strongly imply botanical-only status.
_BOTANICAL_ONLY_KEYWORDS: tuple[str, ...] = (
    "parasitic plant",
    "obligate parasite",
    "grows inside host",
    "endoparasite",
    "no roots",
    "no stems",
    "no leaves",
    "host vine",
    "tetrastigma",          # Rafflesia's host genus
    "not commercially available",
    "cannot be cultivated",
    "cannot be grown",
    "botanical institution",
    "scientific program",
    "protected forest",
    "forest reserve",
    "botanical garden only",
)

# ── Advanced collector ────────────────────────────────────────────────────────
# Specialist plants available through dedicated collectors / specialist growers.
# High skill requirement; not suitable for beginners.

_ADVANCED_COLLECTOR_GENERA: set[str] = {
    "nepenthes",       # tropical pitcher plants; highland spp. need cool misting
    "dionaea",         # venus flytrap; requires pure water, dormancy, etc.
    "sarracenia",      # north american pitcher plants
    "drosera",         # sundews (many spp. need specific humidity/substrate)
    "heliamphora",     # south american sun pitchers; very specialist
    "cephalotus",      # albany pitcher plant; very difficult
    "paphiopedilum",   # slipper orchids; challenging; CITES-regulated species
    "dracula",         # monkey-face orchid; needs cool highland conditions
    "dischidia",       # epiphytic; many spp. tricky to maintain
}

_ADVANCED_COLLECTOR_COMMON_NAMES: set[str] = {
    "venus flytrap",
    "venus fly trap",
    "pitcher plant",
    "slipper orchid",
    "monkey orchid",
    "monkey-face orchid",
    "sundew",
    "butterwort",
}

# ── Specialty garden ──────────────────────────────────────────────────────────
# Available at good nurseries; more challenging than common garden plants
# but achievable by enthusiastic home gardeners.

_SPECIALTY_GENERA: set[str] = {
    "medinilla",
    "tacca",            # bat flower
    "strongylodon",     # jade vine
    "strelitzia",       # bird of paradise
    "gloriosa",         # glory lily
    "amherstia",        # pride of Burma
    "thunbergia",       # clockvine; some spp. need management
}

_SPECIALTY_COMMON_NAMES: set[str] = {
    "bat flower",
    "black bat flower",
    "jade vine",
    "bird of paradise",
    "glory lily",
    "pride of burma",
    "giant orchid",
}


# ── Special plants ────────────────────────────────────────────────────────────
# Plants that should NEVER have nursery prices, popularity rankings,
# garden location recommendations, watering schedules, or similar plant
# suggestions shown to the user.  These are either legally protected,
# parasitic, require institutional care, or are practically impossible
# to obtain / cultivate by any home gardener.
_SPECIAL_PLANTS: set[str] = {
    # Rafflesia
    "rafflesia",
    "rafflesia arnoldii",
    "rafflesia hasseltii",
    "rafflesia keithii",
    "rafflesia pricei",
    "rafflesia cantleyi",
    "corpse flower",
    "corpse lily",
    # Titan arum
    "amorphophallus titanum",
    "titan arum",
    "titan lily",
    # Giant water lilies
    "victoria amazonica",
    "victoria cruziana",
    "giant water lily",
    "amazon water lily",
    "victoria water lily",
    # Orchids – ultra-rare
    "ghost orchid",
    "epipogium aphyllum",
    "dendrophylax lindenii",
    # Welwitschia
    "welwitschia",
    "welwitschia mirabilis",
    # Nepenthes rajah
    "nepenthes rajah",
    # Wollemia
    "wollemia",
    "wollemi pine",
    "wollemia nobilis",
    # Other parasitic / institutional plants
    "rhizanthes",
    "sapria",
    "mitrastema",
    "cytinus",
}


# ── Hardcoded botanical facts for known special plants ────────────────────────
# Keyed by lowercase genus name.  Used by get_botanical_info().
_BOTANICAL_FACTS: dict[str, dict] = {
    "rafflesia": {
        "is_largest_flower": True,
        "flower_diameter": "Up to 106 cm (42 inches)",
        "flower_lifespan": "5–7 days",
        "native_region": "Borneo and Sumatra rainforests, Southeast Asia",
        "conservation_status": "Critically Endangered",
        "host_plant": "Tetrastigma vine (family Vitaceae)",
        "host_plant_required": True,
        "habitat": "Undisturbed lowland tropical rainforest",
        "cultivation_note": (
            "Cannot be cultivated outside its natural rainforest habitat. "
            "Requires a living Tetrastigma host vine and specific undisturbed forest conditions "
            "that cannot be replicated in a home garden."
        ),
        "interesting_facts": [
            "Produces the world's largest individual flower — up to 106 cm across and weighing up to 11 kg",
            "Has no roots, stems, leaves, or chlorophyll — lives entirely as a parasite inside the host vine",
            "Emits a strong odour of rotting flesh to attract carrion flies as pollinators",
            "A single flower bud takes 9–12 months to develop before blooming",
            "Each bloom lasts only 5–7 days before collapsing",
            "Listed as Critically Endangered due to deforestation and habitat destruction",
        ],
    },
    "rhizanthes": {
        "is_largest_flower": False,
        "flower_diameter": "Up to 25 cm",
        "flower_lifespan": "3–5 days",
        "native_region": "Southeast Asia rainforests",
        "conservation_status": "Endangered",
        "host_plant": "Tetrastigma vine (family Vitaceae)",
        "host_plant_required": True,
        "habitat": "Undisturbed lowland tropical rainforest",
        "cultivation_note": (
            "A close relative of Rafflesia. Also a holoparasite on Tetrastigma vines. "
            "Impossible to cultivate outside its natural forest habitat."
        ),
        "interesting_facts": [
            "A holoparasitic plant closely related to Rafflesia",
            "Completely dependent on the host Tetrastigma vine for all nutrients",
            "Has no photosynthetic tissue whatsoever",
        ],
    },
    "sapria": {
        "is_largest_flower": False,
        "flower_diameter": "15–20 cm",
        "flower_lifespan": "3–5 days",
        "native_region": "Southeast Asia and South Asia rainforests",
        "conservation_status": "Endangered",
        "host_plant": "Tetrastigma vine (family Vitaceae)",
        "host_plant_required": True,
        "habitat": "Tropical rainforest",
        "cultivation_note": "A holoparasitic relative of Rafflesia. Cannot be cultivated outside its natural forest habitat.",
        "interesting_facts": [
            "Another member of the Rafflesiaceae family — a holoparasite on Tetrastigma vines",
            "Found in deep rainforest; essentially impossible to cultivate outside nature",
        ],
    },
    "amorphophallus": {
        "is_largest_flower": False,
        "flower_diameter": "N/A — it is a single unbranched inflorescence up to 3 m tall",
        "flower_lifespan": "24–48 hours per bloom",
        "native_region": "Sumatra rainforests, Indonesia",
        "conservation_status": "Vulnerable (Amorphophallus titanum)",
        "host_plant": "None — grows from a large underground corm",
        "host_plant_required": False,
        "habitat": "Equatorial rainforest with deep, rich volcanic soil",
        "cultivation_note": (
            "Requires a massive corm (can exceed 70 kg), a very large space, "
            "and precise tropical temperature and humidity. "
            "Rarely feasible for home gardening."
        ),
        "interesting_facts": [
            "Produces the world's largest unbranched inflorescence — up to 3 metres tall",
            "Also known as the Titan Arum or Corpse Flower for its intense rotting-flesh odour",
            "The underground corm can weigh over 70 kg",
            "Blooms unpredictably, sometimes only once every 7–10 years",
            "Listed as Vulnerable due to habitat destruction in Sumatra",
        ],
    },
    "victoria": {
        "is_largest_flower": False,
        "flower_diameter": "20–40 cm",
        "flower_lifespan": "2 nights (white on first night, pink on second)",
        "native_region": "Amazon River basin, South America",
        "conservation_status": "Least Concern",
        "host_plant": "None — fully aquatic",
        "host_plant_required": False,
        "habitat": "Warm, shallow tropical rivers and oxbow lakes",
        "cultivation_note": (
            "Giant pads can reach 3 m in diameter. "
            "Requires a very large heated pond (minimum 22°C) with intense tropical sunlight. "
            "Not suitable for home garden ponds or containers."
        ),
        "interesting_facts": [
            "Giant lily pads can reach up to 3 metres in diameter and support the weight of a small child",
            "Flowers change from white to pink over two nights, using heat to attract beetles for pollination",
            "Requires water temperatures of at least 22°C and intense full sun",
            "Named after Queen Victoria by the botanist John Lindley in 1837",
        ],
    },
    "welwitschia": {
        "is_largest_flower": False,
        "flower_diameter": "N/A — produces small cones, not flowers",
        "flower_lifespan": "N/A",
        "native_region": "Namib Desert, Namibia and Angola",
        "conservation_status": "Least Concern (a living fossil)",
        "host_plant": "None",
        "host_plant_required": False,
        "habitat": "Namib Desert coastal fog zone — one of the driest places on Earth",
        "cultivation_note": (
            "Requires the extreme aridity and coastal fog of the Namib Desert. "
            "Cannot survive Malaysia's tropical humidity. "
            "Essentially impossible to cultivate outside its native desert climate."
        ),
        "interesting_facts": [
            "Can live for over 1,000 years — some specimens are estimated to be 2,000 years old",
            "Produces only two leaves in its entire lifetime, which keep growing and splitting",
            "Is a gymnosperm (cone-bearer), more closely related to conifers than to flowering plants",
            "Survives almost entirely on coastal fog moisture in the Namib Desert",
            "Known as a 'living fossil' — the only surviving member of its order",
        ],
    },
    "wollemia": {
        "is_largest_flower": False,
        "flower_diameter": "N/A — a conifer, produces cones",
        "flower_lifespan": "N/A",
        "native_region": "Wollemi National Park, New South Wales, Australia",
        "conservation_status": "Critically Endangered (fewer than 100 wild trees known)",
        "host_plant": "None",
        "host_plant_required": False,
        "habitat": "Deep sandstone gorges in temperate Australian bushland",
        "cultivation_note": (
            "Critically Endangered with fewer than 100 wild trees known. "
            "Trade is strictly controlled. "
            "Requires temperate conditions — incompatible with Malaysia's tropical climate."
        ),
        "interesting_facts": [
            "Discovered in 1994; previously known only from 200-million-year-old fossils",
            "Fewer than 100 wild trees are known to exist in a secret location in Australia",
            "The exact location is kept secret to protect the trees from human disturbance",
            "Can grow to 40 m tall in its native habitat",
        ],
    },
}


def get_botanical_info(plant_name: str, scientific_name: str) -> dict | None:
    """Return hardcoded accurate botanical facts for known special plants.

    Returns None if no entry is found (caller may fall back to AI-generated data).
    Lookup order: genus from scientific name → keyword in common or scientific name.
    """
    sci_lc  = (scientific_name or "").lower().strip()
    name_lc = (plant_name or "").lower().strip()

    # Genus from scientific name is the most reliable key
    genus = sci_lc.split()[0].strip("×.,'\"") if sci_lc else ""
    if genus and genus in _BOTANICAL_FACTS:
        return _BOTANICAL_FACTS[genus]

    # Fallback: keyword scan against both name and scientific name
    for key, facts in _BOTANICAL_FACTS.items():
        if key in name_lc or key in sci_lc:
            return facts

    return None


def is_special_plant(plant_name: str, scientific_name: str, category: str) -> bool:
    """Return True if this plant should be treated as a special/botanical-only plant
    that suppresses home-garden recommendations.

    Detection order:
      1. All botanical_only category plants are special
      2. Explicit SPECIAL_PLANTS list (common name OR scientific name)
    """
    if category == "botanical_only":
        return True

    name_lc = (plant_name or "").lower().strip()
    sci_lc  = (scientific_name or "").lower().strip()

    for entry in _SPECIAL_PLANTS:
        if entry in name_lc or entry in sci_lc:
            print(f"[cultivation] is_special_plant MATCH on entry={entry!r} for plant={plant_name!r} sci={scientific_name!r}")
            return True

    result = False
    print(f"[cultivation] is_special_plant({plant_name!r}, {scientific_name!r}, category={category!r}) → {result}")
    return result


def get_cultivation_category(
    plant_name: str,
    scientific_name: str,
    description: str = "",
    difficulty: str = "",
) -> str:
    """
    Return one of:
        'common_garden' | 'specialty_garden' | 'advanced_collector' | 'botanical_only'

    Lookup order:
        1. Botanical-only genus check
        2. Botanical-only species (exact)
        3. Botanical-only common name
        4. Botanical-only keyword scan in description/name
        5. Advanced-collector genus check
        6. Advanced-collector common name
        7. Specialty genus / common name
        8. Difficulty-based fallback (Hard → specialty_garden)
        9. Default: common_garden
    """
    name_lc = (plant_name or "").lower().strip()
    sci_lc  = (scientific_name or "").lower().strip()
    desc_lc = (description or "").lower()
    diff_lc = (difficulty or "").lower()

    print(f"[cultivation] get_cultivation_category: plant={plant_name!r} sci={scientific_name!r} diff={difficulty!r}")

    # Extract genus from scientific name
    genus = ""
    if sci_lc:
        genus = sci_lc.split()[0].strip("×.,'\"")

    # ── 1. Botanical-only: genus ──────────────────────────────────────────────
    if genus and genus in _BOTANICAL_ONLY_GENERA:
        print(f"[cultivation] → botanical_only (genus match: {genus!r})")
        return "botanical_only"

    # ── 2. Botanical-only: exact species ─────────────────────────────────────
    if sci_lc in _BOTANICAL_ONLY_SPECIES:
        print(f"[cultivation] → botanical_only (species match: {sci_lc!r})")
        return "botanical_only"

    # ── 3. Botanical-only: common name ───────────────────────────────────────
    for cn in _BOTANICAL_ONLY_COMMON_NAMES:
        if cn in name_lc:
            print(f"[cultivation] → botanical_only (common name match: {cn!r})")
            return "botanical_only"

    # ── 4. Botanical-only: keywords in description or plant name ─────────────
    search_text = f"{name_lc} {desc_lc}"
    matched_kw = next((kw for kw in _BOTANICAL_ONLY_KEYWORDS if kw in search_text), None)
    if matched_kw:
        print(f"[cultivation] → botanical_only (keyword match: {matched_kw!r})")
        return "botanical_only"

    # ── 5. Advanced-collector: genus ─────────────────────────────────────────
    if genus and genus in _ADVANCED_COLLECTOR_GENERA:
        print(f"[cultivation] → advanced_collector (genus: {genus!r})")
        return "advanced_collector"

    # ── 6. Advanced-collector: common name ───────────────────────────────────
    for cn in _ADVANCED_COLLECTOR_COMMON_NAMES:
        if cn in name_lc:
            print(f"[cultivation] → advanced_collector (common name: {cn!r})")
            return "advanced_collector"

    # ── 7. Specialty garden ───────────────────────────────────────────────────
    if genus and genus in _SPECIALTY_GENERA:
        print(f"[cultivation] → specialty_garden (genus: {genus!r})")
        return "specialty_garden"

    for cn in _SPECIALTY_COMMON_NAMES:
        if cn in name_lc:
            print(f"[cultivation] → specialty_garden (common name: {cn!r})")
            return "specialty_garden"

    # ── 8. Difficulty-based fallback ─────────────────────────────────────────
    if diff_lc == "hard":
        category_result = "specialty_garden"
    else:
        # ── 9. Default ────────────────────────────────────────────────────────
        category_result = "common_garden"

    print(f"[cultivation] get_cultivation_category({plant_name!r}, {scientific_name!r}) fallback → {category_result!r}")
    return category_result


# ── Aquatic / water-garden plant location rules ──────────────────────────────
# Values: True = recommended  |  False = not suitable
#         "conditional:Note text" = possible with specific conditions (🟡 in UI)
#
# Lookup keys are lowercase common names, scientific names, or genera.
# The first matching entry wins.

_AQUATIC_LOCATION_RULES: dict[str, dict] = {
    # Lotus — can be grown in water tubs / container ponds on balcony or porch
    "nelumbo nucifera": {
        "balcony":    "conditional:Possible with large water container (min. 50L) and at least 6h direct sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "nelumbo": {
        "balcony":    "conditional:Possible with large water container (min. 50L) and at least 6h direct sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "lotus": {
        "balcony":    "conditional:Possible with large water container (min. 50L) and at least 6h direct sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    # Water Lily — shallower container is fine; also balcony-viable
    "nymphaea": {
        "balcony":    "conditional:Suitable in a wide, shallow container pond (min. 40L) with full sun",
        "front_yard": True,
        "porch":      "conditional:Suitable in a wide container pond with at least 5h direct sun",
        "indoor":     False,
    },
    "water lily": {
        "balcony":    "conditional:Suitable in a wide, shallow container pond (min. 40L) with full sun",
        "front_yard": True,
        "porch":      "conditional:Suitable in a wide container pond with at least 5h direct sun",
        "indoor":     False,
    },
    "water hyacinth": {
        "balcony":    "conditional:Suitable in a large bucket or water tub with full sun; monitor for rapid spread",
        "front_yard": True,
        "porch":      "conditional:Suitable in a large water tub with full sun",
        "indoor":     False,
    },
    "eichhornia": {
        "balcony":    "conditional:Suitable in a large bucket or water tub with full sun; monitor for rapid spread",
        "front_yard": True,
        "porch":      "conditional:Suitable in a large water tub with full sun",
        "indoor":     False,
    },
    # Papyrus — tall; balcony possible in large pot with water saucer
    "cyperus papyrus": {
        "balcony":    "conditional:Possible in a large pot with standing water and full sun; needs wind protection",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "papyrus": {
        "balcony":    "conditional:Possible in a large pot with standing water and full sun; needs wind protection",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    # Pickerel Weed
    "pontederia": {
        "balcony":    "conditional:Suitable in a wide water container (min. 40L) with full sun",
        "front_yard": True,
        "porch":      "conditional:Suitable in a water container with at least 5h direct sun",
        "indoor":     False,
    },
    "pickerel weed": {
        "balcony":    "conditional:Suitable in a wide water container (min. 40L) with full sun",
        "front_yard": True,
        "porch":      "conditional:Suitable in a water container with at least 5h direct sun",
        "indoor":     False,
    },
    "pickerelweed": {
        "balcony":    "conditional:Suitable in a wide water container (min. 40L) with full sun",
        "front_yard": True,
        "porch":      "conditional:Suitable in a water container with at least 5h direct sun",
        "indoor":     False,
    },
}


def get_aquatic_location_override(plant_name: str, scientific_name: str) -> dict | None:
    """Return location override rules for aquatic/water-garden plants, or None.

    Returns a dict mapping location keys to True, False, or "conditional:note".
    The first matching entry in _AQUATIC_LOCATION_RULES wins.
    """
    name_lc = (plant_name or "").lower().strip()
    sci_lc  = (scientific_name or "").lower().strip()
    genus   = sci_lc.split()[0].strip("×.,'\") ") if sci_lc else ""

    # Check exact scientific name, genus, then common name substrings
    for key, rules in _AQUATIC_LOCATION_RULES.items():
        if key == sci_lc or key == genus or key in name_lc:
            print(f"[cultivation] aquatic override matched {key!r} for {plant_name!r}")
            return rules

    return None


# ── Container-garden location overrides ──────────────────────────────────────
# Correct AI bias that marks ornamental shrubs as balcony=False.
# In Malaysia, most flowering shrubs, herbs, succulents, and orchids are
# routinely grown in pots on balconies and covered porches.
#
# Values: True = recommended  |  False = not suitable
#         "conditional:note"  = possible with specific conditions (🟡 in UI)
#
# Lookup keys: lowercase scientific genus, exact scientific name, or common-name substring.

_CONTAINER_GARDEN_OVERRIDES: dict[str, dict] = {

    # ── Roses ─────────────────────────────────────────────────────────────────
    "rosa": {
        "balcony":    True,
        "front_yard": True,
        "porch":      "conditional:Needs 6h+ direct sun daily; use pot ≥30L with well-draining mix",
        "indoor":     False,
    },
    "rose": {
        "balcony":    True,
        "front_yard": True,
        "porch":      "conditional:Needs 6h+ direct sun daily; use pot ≥30L with well-draining mix",
        "indoor":     False,
    },

    # ── Hibiscus ──────────────────────────────────────────────────────────────
    "hibiscus": {
        "balcony":    True,
        "front_yard": True,
        "porch":      "conditional:Needs at least 4h direct sun; thrives in large pots",
        "indoor":     False,
    },

    # ── Bougainvillea ─────────────────────────────────────────────────────────
    "bougainvillea": {
        "balcony":    True,
        "front_yard": True,
        "porch":      "conditional:Needs full sun and trellis support; use large container (40L+)",
        "indoor":     False,
    },

    # ── Desert Rose (Adenium) — almost exclusively a container plant ──────────
    "adenium": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "desert rose": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Gardenia ──────────────────────────────────────────────────────────────
    "gardenia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Plumeria / Frangipani ─────────────────────────────────────────────────
    "plumeria": {
        "balcony":    True,
        "front_yard": True,
        "porch":      "conditional:Needs full sun; use large container (30L+)",
        "indoor":     False,
    },

    # ── Ixora (both species) ──────────────────────────────────────────────────
    "ixora": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Lantana ───────────────────────────────────────────────────────────────
    "lantana": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Pentas ────────────────────────────────────────────────────────────────
    "pentas": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Plumbago ──────────────────────────────────────────────────────────────
    "plumbago": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Crossandra ────────────────────────────────────────────────────────────
    "crossandra": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Salvia ────────────────────────────────────────────────────────────────
    "salvia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Mexican Heather (Cuphea) — compact, ideal container plant ─────────────
    "cuphea": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "mexican heather": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Tibouchina ────────────────────────────────────────────────────────────
    "tibouchina": {
        "balcony":    "conditional:Use large pot (40L+); needs full sun and regular pruning",
        "front_yard": True,
        "porch":      "conditional:Needs good sun; sheltered from strong wind",
        "indoor":     False,
    },

    # ── Kopsia ────────────────────────────────────────────────────────────────
    "kopsia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Tabernaemontana (Pinwheel Flower) ─────────────────────────────────────
    "tabernaemontana": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Hamelia ───────────────────────────────────────────────────────────────
    "hamelia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Brunfelsia ────────────────────────────────────────────────────────────
    "brunfelsia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Mussaenda ─────────────────────────────────────────────────────────────
    "mussaenda": {
        "balcony":    "conditional:Use large container (50L+); needs full sun",
        "front_yard": True,
        "porch":      "conditional:Needs good sun; can get large — prune regularly",
        "indoor":     False,
    },

    # ── Barleria ──────────────────────────────────────────────────────────────
    "barleria": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Ruellia ───────────────────────────────────────────────────────────────
    "ruellia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Acalypha ──────────────────────────────────────────────────────────────
    "acalypha": {
        "balcony":    "conditional:Can get large; use large pot and prune regularly",
        "front_yard": True,
        "porch":      "conditional:Needs bright light; prune to maintain compact size",
        "indoor":     False,
    },

    # ── Turks Cap (Malvaviscus) ────────────────────────────────────────────────
    "malvaviscus": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "turks cap": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Firecracker Plant (Russelia) ──────────────────────────────────────────
    "russelia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Impatiens ─────────────────────────────────────────────────────────────
    "impatiens": {
        "balcony":    "conditional:Bright indirect light; avoid intense afternoon sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Begonia ───────────────────────────────────────────────────────────────
    "begonia": {
        "balcony":    "conditional:Bright indirect light; avoid intense noon sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright window with indirect light",
    },

    # ── Flowering Vines (with trellis) ────────────────────────────────────────
    "allamanda": {
        "balcony":    "conditional:Needs full sun and trellis/wall support; use large container",
        "front_yard": True,
        "porch":      "conditional:Needs good sun and trellis support",
        "indoor":     False,
    },
    "mandevilla": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "antigonon": {  # Coral Vine
        "balcony":    "conditional:Needs trellis and full sun; vigorous grower",
        "front_yard": True,
        "porch":      "conditional:Needs trellis and good sun",
        "indoor":     False,
    },
    "coral vine": {
        "balcony":    "conditional:Needs trellis and full sun; vigorous grower",
        "front_yard": True,
        "porch":      "conditional:Needs trellis and good sun",
        "indoor":     False,
    },
    "thunbergia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "black-eyed susan vine": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "clerodendrum": {
        "balcony":    "conditional:Use large container (40L+); provide trellis support",
        "front_yard": True,
        "porch":      "conditional:Needs good light and trellis support",
        "indoor":     False,
    },

    # ── Tropical Flowering Plants ─────────────────────────────────────────────
    "heliconia": {
        "balcony":    "conditional:Very large container (80L+) required; shelter from strong wind",
        "front_yard": True,
        "porch":      "conditional:Large container required; needs bright indirect light",
        "indoor":     False,
    },
    "anthurium": {
        "balcony":    "conditional:Bright indirect light only; protect from direct harsh sun",
        "front_yard": "conditional:Partial shade only; avoid direct noon sun",
        "porch":      True,
        "indoor":     True,
    },
    "strelitzia": {
        "balcony":    "conditional:Large container (60L+) required; needs full sun; sheltered from wind",
        "front_yard": True,
        "porch":      "conditional:Large container required; needs bright sun",
        "indoor":     False,
    },
    "bird of paradise": {
        "balcony":    "conditional:Large container (60L+) required; needs full sun; sheltered from wind",
        "front_yard": True,
        "porch":      "conditional:Large container required; needs bright sun",
        "indoor":     False,
    },
    "canna": {
        "balcony":    "conditional:Use large pot (40L+) filled with rich compost; full sun",
        "front_yard": True,
        "porch":      "conditional:Large container required; needs at least 4h direct sun",
        "indoor":     False,
    },
    "canna lily": {
        "balcony":    "conditional:Use large pot (40L+) filled with rich compost; full sun",
        "front_yard": True,
        "porch":      "conditional:Large container required; needs at least 4h direct sun",
        "indoor":     False,
    },
    "hedychium": {  # Ginger Lily
        "balcony":    "conditional:Large container required; full sun to partial shade",
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "caladium": {
        "balcony":    "conditional:Partial to full shade; avoid direct harsh sun",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Bright indirect light; keep warm and humid",
    },
    "medinilla": {
        "balcony":    "conditional:Bright indirect light; protect from direct harsh sun",
        "front_yard": "conditional:Partial shade; protect from afternoon sun",
        "porch":      True,
        "indoor":     "conditional:Bright indirect light; high humidity",
    },

    # ── Succulents — all highly container-friendly ────────────────────────────
    "adenium obesum": {  # exact species for Desert Rose
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "aloe": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright south- or west-facing window",
    },
    "euphorbia milii": {  # Crown of Thorns — not all Euphorbia
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "crown of thorns": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "crassula": {  # Jade Plant
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright window with 4h+ indirect light",
    },
    "echeveria": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright south-facing window; avoid overwatering",
    },
    "haworthia": {
        "balcony":    "conditional:Bright indirect light; avoid intense direct noon sun",
        "front_yard": "conditional:Partial shade; protect from afternoon sun",
        "porch":      True,
        "indoor":     True,
    },
    "kalanchoe": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright window; short-day flowering plant",
    },

    # ── Orchids — excellent for covered balconies in Malaysia ─────────────────
    "dendrobium": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "phalaenopsis": {
        "balcony":    "conditional:Bright indirect light; no direct harsh sun; ideal under eaves",
        "front_yard": False,
        "porch":      True,
        "indoor":     True,
    },
    "vanda": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "oncidium": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "cattleya": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "spathoglottis": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Palms — small/container varieties ─────────────────────────────────────
    "rhapis": {  # Lady Palm
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Bright room with indirect light; slow grower",
    },
    "lady palm": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Bright room with indirect light; slow grower",
    },
    "phoenix roebelenii": {  # Pygmy Date Palm
        "balcony":    "conditional:Large container (50L+); shelter from strong wind",
        "front_yard": True,
        "porch":      "conditional:Large container; needs good bright light",
        "indoor":     False,
    },
    "pygmy date palm": {
        "balcony":    "conditional:Large container (50L+); shelter from strong wind",
        "front_yard": True,
        "porch":      "conditional:Large container; needs good bright light",
        "indoor":     False,
    },
    "howea": {  # Kentia Palm
        "balcony":    "conditional:Large container; bright indirect light; wind-sensitive",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Brightest room available; tolerates lower light than most palms",
    },
    "dypsis": {  # Areca Palm
        "balcony":    "conditional:Large container; bright indirect light; wind-sensitive",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright room; mist leaves regularly",
    },
    "areca palm": {
        "balcony":    "conditional:Large container; bright indirect light; wind-sensitive",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright room; mist leaves regularly",
    },

    # ── Herbs — universally container-friendly ────────────────────────────────
    "pandanus": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "pandan": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "cymbopogon": {  # Lemongrass
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "lemongrass": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "ocimum": {  # Basil
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright south-facing window",
    },
    "basil": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright south-facing window",
    },
    "mentha": {  # Mint
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright window; keep moist",
    },
    "mint": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright window; keep moist",
    },
    "murraya koenigii": {  # Curry Leaf
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "curry leaf": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "citrus hystrix": {  # Kaffir Lime
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "kaffir lime": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "citrus aurantifolia": {  # Lime
        "balcony":    "conditional:Large container (50L+); full sun; regular fertilising",
        "front_yard": True,
        "porch":      "conditional:Full sun required; large container",
        "indoor":     False,
    },
    "capsicum": {  # Chilli
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "chilli": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Ferns ─────────────────────────────────────────────────────────────────
    "nephrolepis": {  # Boston Fern
        "balcony":    "conditional:Partial to full shade; no direct sun; high humidity required",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Bright indirect light; mist leaves daily",
    },
    "boston fern": {
        "balcony":    "conditional:Partial to full shade; no direct sun; high humidity required",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Bright indirect light; mist leaves daily",
    },
    "asplenium": {  # Bird's Nest Fern
        "balcony":    "conditional:Shade only; no direct sun; high humidity required",
        "front_yard": True,
        "porch":      True,
        "indoor":     True,
    },
    "birds nest fern": {
        "balcony":    "conditional:Shade only; no direct sun; high humidity required",
        "front_yard": True,
        "porch":      True,
        "indoor":     True,
    },
    "platycerium": {  # Staghorn Fern
        "balcony":    "conditional:Mount on board or hang; bright indirect light; high humidity",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright indirect light; mount on board",
    },
    "staghorn fern": {
        "balcony":    "conditional:Mount on board or hang; bright indirect light; high humidity",
        "front_yard": True,
        "porch":      True,
        "indoor":     "conditional:Very bright indirect light; mount on board",
    },

    # ── Groundcovers ──────────────────────────────────────────────────────────
    "portulaca": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "torenia": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "evolvulus": {  # Blue Daze
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },
    "blue daze": {
        "balcony":    True,
        "front_yard": True,
        "porch":      True,
        "indoor":     False,
    },

    # ── Trees — fruit trees in containers ─────────────────────────────────────
    "callistemon": {  # Bottlebrush
        "balcony":    "conditional:Dwarf varieties only; large container (50L+); full sun",
        "front_yard": True,
        "porch":      False,
        "indoor":     False,
    },
    "bottlebrush": {
        "balcony":    "conditional:Dwarf varieties only; large container (50L+); full sun",
        "front_yard": True,
        "porch":      False,
        "indoor":     False,
    },
}


def get_location_override(plant_name: str, scientific_name: str) -> dict | None:
    """Return location override rules for a plant, or None.

    Checks aquatic overrides first (most specific), then container-garden overrides.
    Returns a dict mapping location keys to True, False, or "conditional:note text".
    The first matching entry wins.
    """
    # Aquatic plants first
    aquatic = get_aquatic_location_override(plant_name, scientific_name)
    if aquatic:
        return aquatic

    # Container-garden overrides — sort keys longest-first so "desert rose"
    # matches before "rose", "bird of paradise" before "paradise", etc.
    name_lc = (plant_name or "").lower().strip()
    sci_lc  = (scientific_name or "").lower().strip()
    genus   = sci_lc.split()[0].strip("×.,'\") ") if sci_lc else ""

    for key, rules in sorted(_CONTAINER_GARDEN_OVERRIDES.items(), key=lambda x: -len(x[0])):
        if key == sci_lc or key == genus or key in name_lc:
            print(f"[cultivation] container override matched {key!r} for {plant_name!r}")
            return rules

    return None


# ── Score band definitions (single source of truth) ─────────────────────────
# These are the canonical bands used by the entire scoring pipeline.
# Every score produced by get_gardenability_score() falls into one of these.
#
#  81-100  Highly Recommended — ideal for Malaysian home gardens
#  61-80   Recommended        — grows well with standard care
#  41-60   Moderate           — needs extra care / specific conditions
#  21-40   Challenging        — demanding; not beginner-friendly
#  10-20   Not Recommended    — unsuitable for home cultivation
#   0-9    Botanical Only     — botanical / conservation only

_SCORE_BANDS: tuple[tuple[int, int, str, str], ...] = (
    # (min_inclusive, max_inclusive, label, short_label)
    (81, 100, "Highly Recommended",              "Highly Recommended"),
    (61,  80, "Recommended",                      "Recommended"),
    (41,  60, "Moderate",                         "Moderate"),
    (21,  40, "Challenging",                      "Challenging"),
    (10,  20, "Not Recommended",                  "Not Recommended"),
    (0,    9, "Botanical Only",                   "Botanical Only"),
)


def get_score_band(score: int) -> dict:
    """Return the human-readable band dict for a given 0-100 score.

    Returns a dict with keys:
        label        – full label, e.g. "Recommended"
        short_label  – compact label, e.g. "Recommended"
        min          – lower bound of band (inclusive)
        max          – upper bound of band (inclusive)
    """
    for min_s, max_s, label, short_label in _SCORE_BANDS:
        if min_s <= score <= max_s:
            return {"label": label, "short_label": short_label, "min": min_s, "max": max_s}
    # Fallback (score outside 0-100 shouldn't happen)
    return {"label": "Unknown", "short_label": "Unknown", "min": 0, "max": 0}


def get_gardenability_score(category: str, difficulty: str = "") -> int:
    """
    Compute a holistic home-garden suitability score (0-100).

    Canonical score bands:
      81-100  Highly Recommended — ideal for Malaysian home gardens
      61-80   Recommended        — grows well with standard care
      41-60   Moderate           — needs extra care / specific conditions
      21-40   Challenging        — demanding; not beginner-friendly
      10-20   Not Recommended    — unsuitable for home cultivation
       0-9    Botanical Only     — botanical / conservation only

    Category → difficulty → score mapping:
      botanical_only                       →  5  (Botanical Only)
      advanced_collector  + hard           → 25  (Challenging)
      advanced_collector  + medium         → 30  (Challenging)
      advanced_collector  + easy/default   → 35  (Challenging)
      specialty_garden    + hard           → 45  (Moderate)
      specialty_garden    + medium         → 52  (Moderate)
      specialty_garden    + easy/default   → 58  (Moderate)
      common_garden       + hard           → 65  (Recommended)
      common_garden       + medium         → 72  (Recommended)
      common_garden       + easy/default   → 85  (Highly Recommended)
    """
    diff = (difficulty or "").lower().strip()

    if category == "botanical_only":
        score = 5   # Botanical Only band (0-9)

    elif category == "advanced_collector":
        if diff == "hard":
            score = 25  # Challenging band (21-40)
        elif diff == "medium":
            score = 30  # Challenging band
        else:
            score = 35  # Challenging band

    elif category == "specialty_garden":
        if diff == "hard":
            score = 45  # Moderate band (41-60)
        elif diff == "medium":
            score = 52  # Moderate band
        else:
            score = 58  # Moderate band

    else:  # common_garden
        if diff == "hard":
            score = 65  # Recommended band (61-80)
        elif diff == "medium":
            score = 72  # Recommended band
        else:
            score = 85  # Highly Recommended band (81-100)

    print(f"[cultivation] get_gardenability_score(category={category!r}, difficulty={difficulty!r}) → {score}")
    return score
