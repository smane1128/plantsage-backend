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
# "watering_days": default reminder interval (days) — conservative pot estimate
# "watering_range": "min-max" display string (pot hot season to pot cool/rainy season)
# "watering_ground": "min-max" display string for in-ground plants
# "tasks": task_type → interval_days  (absent key = task not applicable for this plant)
_SPECIES_DATA: list[dict[str, Any]] = [

    # ── Annuals / short crops ────────────────────────────────────────────────
    {
        "scientific": ["helianthus annuus"],
        "common":     ["sunflower"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["lactuca sativa"],
        "common":     ["lettuce", "selada"],
        "lifespan_days": 75,
        "watering_days": 1, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["zinnia elegans", "zinnia"],
        "common":     ["zinnia"],
        "lifespan_days": 70,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["tagetes erecta", "tagetes patula", "tagetes"],
        "common":     ["marigold", "african marigold", "french marigold"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
    },
    {
        "scientific": ["cosmos bipinnatus", "cosmos sulphureus"],
        "common":     ["cosmos"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["brassica rapa subsp. chinensis", "brassica rapa"],
        "common":     ["pak choi", "bok choy", "pok choy", "sawi"],
        "lifespan_days": 60,
        "watering_days": 1, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["ipomoea aquatica"],
        "common":     ["kangkung", "water spinach", "morning glory vegetable"],
        "lifespan_days": 45,
        "watering_days": 1, "watering_range": "1", "watering_ground": "1",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["amaranthus tricolor", "amaranthus viridis", "amaranthus"],
        "common":     ["bayam", "amaranth"],
        "lifespan_days": 45,
        "watering_days": 1, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["cucumis sativus"],
        "common":     ["cucumber", "timun"],
        "lifespan_days": 75,
        "watering_days": 1, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 14, "pest_check": 7},
    },
    {
        "scientific": ["raphanus sativus"],
        "common":     ["radish", "lobak"],
        "lifespan_days": 30,
        "watering_days": 1, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 14, "pest_check": 14},
    },
    {
        "scientific": ["coriandrum sativum"],
        "common":     ["coriander", "cilantro", "daun ketumbar"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "1-2",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["allium fistulosum", "allium schoenoprasum"],
        "common":     ["spring onion", "scallion", "chives", "daun bawang"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },

    # ── Short perennials / grown as annuals ──────────────────────────────────
    {
        "scientific": ["solanum lycopersicum"],
        "common":     ["tomato", "tomatoes", "tomat"],
        "lifespan_days": 150,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
    },
    {
        "scientific": ["capsicum annuum", "capsicum frutescens"],
        "common":     ["chili", "chilli", "pepper", "cili"],
        "lifespan_days": 365,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "2-4",
        "tasks": {"fertilize": 21, "prune": 60, "pest_check": 14},
    },
    {
        "scientific": ["ocimum basilicum"],
        "common":     ["basil", "sweet basil", "daun selasih"],
        "lifespan_days": 180,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 14, "prune": 14, "pest_check": 14},
    },
    {
        "scientific": ["petroselinum crispum"],
        "common":     ["parsley"],
        "lifespan_days": 365,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 14, "pest_check": 21},
    },

    # ── Long-lived perennials / shrubs ───────────────────────────────────────
    {
        "scientific": ["rosa"],
        "common":     ["rose", "mawar"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 21, "prune": 30, "pest_check": 7},
    },
    {
        "scientific": ["hibiscus rosa-sinensis", "hibiscus"],
        "common":     ["hibiscus", "bunga raya", "rosemallow"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 45, "pest_check": 14},
    },
    {
        "scientific": ["bougainvillea glabra", "bougainvillea spectabilis", "bougainvillea"],
        "common":     ["bougainvillea", "bunga kertas"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "2-4", "watering_ground": "4-7",
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },
    {
        "scientific": ["plumeria rubra", "plumeria obtusa", "plumeria"],
        "common":     ["frangipani", "plumeria", "kamboja"],
        "lifespan_days": None,
        "watering_days": 4, "watering_range": "3-5", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 365, "pest_check": 21},
    },
    {
        # Adenium — drought-tolerant succulent; overwatering is the #1 killer
        "scientific": ["adenium obesum", "adenium arabicum", "adenium"],
        "common":     ["desert rose", "adenium", "impala lily", "mock azalea"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "14-21",
        "tasks": {"fertilize": 30, "pest_check": 14},
    },
    {
        "scientific": ["ixora coccinea", "ixora"],
        "common":     ["ixora", "jungle geranium", "bunga jejarum", "red ixora"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },
    {
        # Jasminum — Star Jasmine / Jasmine Sambac / Bunga Melur
        "scientific": ["jasminum sambac", "jasminum multiflorum", "jasminum officinale",
                       "jasminum polyanthum", "jasminum"],
        "common":     ["jasmine sambac", "jasmine", "bunga melur", "arabian jasmine",
                       "star jasmine jasmine", "mogra"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 30, "pest_check": 14},
    },
    {
        # Trachelospermum jasminoides — Star Jasmine (Confederacy jasmine)
        # Often called "star jasmine" in nurseries but different genus from Jasminum
        "scientific": ["trachelospermum jasminoides", "trachelospermum asiaticum",
                       "trachelospermum"],
        "common":     ["star jasmine", "confederate jasmine", "trachelospermum"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Tabernaemontana — Crape Jasmine / Pinwheel Flower / Mondokaki
        "scientific": ["tabernaemontana divaricata", "tabernaemontana coronaria",
                       "tabernaemontana"],
        "common":     ["crape jasmine", "crepe jasmine", "pinwheel flower",
                       "mondokaki", "tagar", "nero's crown"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["murraya koenigii"],
        "common":     ["curry leaf", "daun kari"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["mentha"],
        "common":     ["mint", "daun pudina"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 14, "pest_check": 14},
    },
    {
        "scientific": ["pandanus amaryllifolius"],
        "common":     ["pandan", "screwpine", "daun pandan"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Pentas lanceolata — Egyptian star cluster, common pot flowering plant
        "scientific": ["pentas lanceolata", "pentas"],
        "common":     ["pentas", "star flower", "egyptian star"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 30, "pest_check": 14},
    },
    {
        # Clerodendrum — Glory bower, Bleeding heart vine
        "scientific": ["clerodendrum thomsoniae", "clerodendrum inerme", "clerodendrum"],
        "common":     ["bleeding heart vine", "glory bower", "clerodendrum"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Catharanthus roseus — Vinca / Periwinkle
        "scientific": ["catharanthus roseus", "catharanthus"],
        "common":     ["vinca", "periwinkle", "madagascar periwinkle"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 14, "prune": 30, "pest_check": 14},
    },
    {
        # Crossandra infundibuliformis — Firecracker flower
        "scientific": ["crossandra infundibuliformis", "crossandra"],
        "common":     ["crossandra", "firecracker flower", "kanakambaram"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 21, "prune": 30, "pest_check": 14},
    },
    {
        # Gardenia jasminoides — Cape Jasmine
        "scientific": ["gardenia jasminoides", "gardenia augusta", "gardenia"],
        "common":     ["gardenia", "cape jasmine"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 21, "prune": 60, "pest_check": 14},
    },
    {
        # Balsam / Touch-me-not (different from Mimosa)
        "scientific": ["impatiens balsamina", "impatiens walleriana", "impatiens"],
        "common":     ["impatiens", "balsam", "busy lizzie", "touch-me-not balsam"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "1-2", "watering_ground": "2-3",
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
    },
    {
        # Celosia — Cockscomb
        "scientific": ["celosia argentea", "celosia cristata", "celosia"],
        "common":     ["celosia", "cockscomb", "woolflower"],
        "lifespan_days": 90,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 7},
    },
    {
        # Dahlia
        "scientific": ["dahlia pinnata", "dahlia"],
        "common":     ["dahlia"],
        "lifespan_days": 180,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 14, "prune": 21, "pest_check": 14},
    },
    {
        # Portulaca / Moss rose
        "scientific": ["portulaca grandiflora", "portulaca oleracea"],
        "common":     ["portulaca", "moss rose", "sun plant"],
        "lifespan_days": 90,
        "watering_days": 3, "watering_range": "3-5", "watering_ground": "5-7",
        "tasks": {"fertilize": 14, "pest_check": 14},
    },
    {
        # Mimosa pudica — Sensitive plant / Touch-me-not / Pokok Semalu
        "scientific": ["mimosa pudica", "mimosa"],
        "common":     ["sensitive plant", "touch-me-not", "semalu", "pokok semalu",
                       "shame plant", "mimosa"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 30, "pest_check": 21},
    },
    {
        # Petrea volubilis — Queen's Wreath
        "scientific": ["petrea volubilis", "petrea"],
        "common":     ["queen's wreath", "queens wreath", "purple wreath", "petrea"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Duranta erecta — Golden Dewdrop / Pigeon Berry
        "scientific": ["duranta erecta", "duranta"],
        "common":     ["duranta", "golden dewdrop", "pigeon berry"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },
    {
        # Lantana camara — Lantana
        "scientific": ["lantana camara", "lantana"],
        "common":     ["lantana", "wild sage"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "2-4", "watering_ground": "4-7",
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 21},
    },

    # ── Succulents ───────────────────────────────────────────────────────────
    {
        "scientific": ["aloe vera", "aloe barbadensis"],
        "common":     ["aloe vera", "aloe"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "10-14", "watering_ground": "14-21",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        "scientific": ["echeveria"],
        "common":     ["echeveria"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "14-21",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        # Sedum / Stonecrop
        "scientific": ["sedum"],
        "common":     ["sedum", "stonecrop"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "14-21",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        # Haworthia
        "scientific": ["haworthia", "haworthiopsis"],
        "common":     ["haworthia", "zebra cactus"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "14-21",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },

    # ── Tropical foliage ─────────────────────────────────────────────────────
    {
        "scientific": ["epipremnum aureum"],
        "common":     ["pothos", "money plant", "devil's ivy"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 30, "pest_check": 14},
    },
    {
        "scientific": ["sansevieria trifasciata", "dracaena trifasciata"],
        "common":     ["snake plant", "mother-in-law's tongue", "lidah mertua"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "10-14",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        "scientific": ["spathiphyllum wallisii", "spathiphyllum"],
        "common":     ["peace lily"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 45, "pest_check": 14},
    },
    {
        "scientific": ["monstera deliciosa", "monstera"],
        "common":     ["monstera", "swiss cheese plant"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 14},
    },
    {
        "scientific": ["ficus benjamina", "ficus lyrata", "ficus elastica"],
        "common":     ["ficus", "rubber plant", "fiddle leaf fig", "weeping fig"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-10",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["caladium bicolor", "caladium"],
        "common":     ["caladium", "keladi"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "2-4", "watering_ground": "3-5",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["aglaonema"],
        "common":     ["aglaonema", "chinese evergreen"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Calathea / Prayer plant
        "scientific": ["calathea", "maranta leuconeura", "maranta"],
        "common":     ["calathea", "prayer plant", "maranta"],
        "lifespan_days": None,
        "watering_days": 4, "watering_range": "3-5", "watering_ground": "4-6",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 14},
    },
    {
        # ZZ Plant
        "scientific": ["zamioculcas zamiifolia", "zamioculcas"],
        "common":     ["zz plant", "zanzibar gem", "zamioculcas"],
        "lifespan_days": None,
        "watering_days": 10, "watering_range": "7-14", "watering_ground": "10-14",
        "tasks": {"fertilize": 60, "pest_check": 30},
    },
    {
        # Chlorophytum / Spider plant
        "scientific": ["chlorophytum comosum", "chlorophytum"],
        "common":     ["spider plant", "chlorophytum"],
        "lifespan_days": None,
        "watering_days": 5, "watering_range": "4-7", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 30, "pest_check": 21},
    },
    {
        # Dracaena / Dragon tree
        "scientific": ["dracaena marginata", "dracaena fragrans", "dracaena"],
        "common":     ["dracaena", "dragon tree", "corn plant"],
        "lifespan_days": None,
        "watering_days": 7, "watering_range": "5-10", "watering_ground": "7-10",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        # Cordyline / Ti plant
        "scientific": ["cordyline fruticosa", "cordyline terminalis", "cordyline"],
        "common":     ["cordyline", "ti plant", "good luck plant", "red ti"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },

    # ── Orchids ──────────────────────────────────────────────────────────────
    {
        "scientific": ["dendrobium", "phalaenopsis", "vanda", "oncidium", "cattleya",
                       "dendrobium phalaenopsis", "dendrobium hybrid"],
        "common":     ["orchid", "dendrobium", "moth orchid", "vanda orchid",
                       "dancing lady orchid", "anggrek"],
        "lifespan_days": None,
        "watering_days": 7, "watering_range": "5-7", "watering_ground": None,
        "tasks": {"fertilize": 14, "pest_check": 21},
    },

    # ── Tropical fruits & edibles ─────────────────────────────────────────────
    {
        "scientific": ["musa paradisiaca", "musa acuminata", "musa balbisiana", "musa"],
        "common":     ["banana", "pisang", "banana tree"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "2-4", "watering_ground": "3-5",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["mangifera indica"],
        "common":     ["mango", "mangga"],
        "lifespan_days": None,
        "watering_days": 4, "watering_range": "3-5", "watering_ground": "5-10",
        "tasks": {"fertilize": 30, "prune": 365, "pest_check": 21},
    },
    {
        "scientific": ["carica papaya"],
        "common":     ["papaya", "betik", "papaw"],
        "lifespan_days": 730,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-5",
        "tasks": {"fertilize": 21, "pest_check": 14},
    },
    {
        "scientific": ["psidium guajava"],
        "common":     ["guava", "jambu batu", "jambu"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "3-5", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 90, "pest_check": 21},
    },
    {
        "scientific": ["averrhoa carambola"],
        "common":     ["starfruit", "star fruit", "belimbing"],
        "lifespan_days": None,
        "watering_days": 3, "watering_range": "3-5", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "prune": 180, "pest_check": 21},
    },
    {
        "scientific": ["ananas comosus"],
        "common":     ["pineapple", "nanas"],
        "lifespan_days": 730,
        "watering_days": 4, "watering_range": "3-5", "watering_ground": "5-7",
        "tasks": {"fertilize": 30, "pest_check": 21},
    },

    # ── Ginger family ─────────────────────────────────────────────────────────
    {
        "scientific": ["zingiber officinale"],
        "common":     ["ginger", "halia"],
        "lifespan_days": 365,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 30, "pest_check": 30},
    },
    {
        "scientific": ["curcuma longa"],
        "common":     ["turmeric", "kunyit"],
        "lifespan_days": 365,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 30, "pest_check": 30},
    },
    {
        "scientific": ["etlingera elatior"],
        "common":     ["torch ginger", "bunga kantan"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
        "tasks": {"fertilize": 30, "prune": 60, "pest_check": 21},
    },
    {
        "scientific": ["alpinia purpurata", "alpinia galanga"],
        "common":     ["red ginger", "galangal", "lengkuas"],
        "lifespan_days": None,
        "watering_days": 2, "watering_range": "2-3", "watering_ground": "3-4",
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
        "watering_days": 3, "watering_range": "3-4", "watering_ground": "5-7",
        "tasks": {"fertilize": 60, "pest_check": 30},
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

# Watering: default reminder interval (days) when no species match exists.
_WATERING_DEFAULTS: dict[str, int] = {
    "succulent":  10,
    "cactus":     14,
    "flower":     2,
    "shrub":      2,
    "tree":       3,
    "vegetable":  2,
    "herb":       2,
    "vine":       2,
    "grass":      3,
    "other":      3,
}
_WATERING_DEFAULT = _WATERING_DEFAULTS["other"]

# Watering recommendation display range (pot: hot→cool season estimate)
_WATERING_DEFAULTS_RANGE: dict[str, str] = {
    "succulent":  "7-14",
    "cactus":     "10-21",
    "flower":     "1-2",
    "shrub":      "1-3",
    "tree":       "2-5",
    "vegetable":  "1-2",
    "herb":       "1-2",
    "vine":       "1-3",
    "grass":      "2-4",
    "other":      "2-3",
}

# Watering recommendation for in-ground plants by type
_WATERING_GROUND_RANGE: dict[str, str] = {
    "succulent":  "14-21",
    "cactus":     "14-30",
    "flower":     "2-3",
    "shrub":      "2-5",
    "tree":       "3-7",
    "vegetable":  "1-2",
    "herb":       "2-3",
    "vine":       "2-4",
    "grass":      "3-5",
    "other":      "3-5",
}

# ── Rich watering care intelligence ──────────────────────────────────────────
# Per-species and per-type data for: finger test, symptom recognition,
# seasonal adjustments and pot-vs-ground guidance.
# Used by get_watering_recommendation() to enrich the returned dict.
#
# Each entry has:
#   finger_test   str       — how to check soil moisture before watering
#   overwatering  list[str] — visible symptoms of overwatering
#   underwatering list[str] — visible symptoms of underwatering
#   hot_season    str       — guidance for Malaysia hot/dry months (Mar-Sep)
#   rainy_season  str       — guidance for monsoon months (Oct-Feb)
#   pot_vs_ground str       — key differences between container and in-ground

_SPECIES_RICH_CARE: dict[str, dict] = {
    "hibiscus rosa-sinensis": {
        "finger_test": "Insert finger 2–3 cm into soil. Water when the top feels dry but not bone-dry.",
        "overwatering": ["Yellowing lower leaves", "Wilting despite moist soil", "Root rot smell from soil"],
        "underwatering": ["Drooping leaves and buds", "Dry crispy leaf edges", "Bud drop"],
        "hot_season": "Water every 1–2 days. Check morning and evening during heatwaves.",
        "rainy_season": "Reduce to every 2–3 days. Ensure pot or bed drains freely.",
        "pot_vs_ground": "Pots dry out quickly — check daily in hot weather. In-ground plants retain moisture longer.",
    },
    "bougainvillea spectabilis": {
        "finger_test": "Insert finger 3–4 cm. Water when soil is almost dry — controlled dryness encourages flowering.",
        "overwatering": ["Very few or no flowers", "Yellow leaves", "Root rot", "Soft stem base"],
        "underwatering": ["Leaf and bract drop", "Wilting stems", "Dry brittle branches"],
        "hot_season": "Water every 2–3 days. Some dryness between waterings actually promotes more blooms.",
        "rainy_season": "Reduce to every 5–7 days. Natural rainfall is usually sufficient for established plants.",
        "pot_vs_ground": "Pot: water every 2–4 days. Ground: established bougainvillea is highly drought-tolerant.",
    },
    "adenium obesum": {
        "finger_test": "Insert finger 5 cm. Water ONLY when completely dry — adenium stores water in its swollen caudex.",
        "overwatering": ["Soft or mushy caudex (often fatal)", "Black rotting roots", "Yellow dropping leaves"],
        "underwatering": ["Wrinkled or shrunken caudex", "Leaf drop", "Pale limp stems"],
        "hot_season": "Water every 7–10 days. Allow full soil dry-out between each watering.",
        "rainy_season": "Water every 14–21 days. Protect from waterlogging — this is the most common cause of death. Ensure excellent drainage.",
        "pot_vs_ground": "Always use pots with large drainage holes and gritty/sandy mix. Heavy garden soil is fatal.",
    },
    "plumeria rubra": {
        "finger_test": "Insert finger 3–4 cm. Water when soil feels almost dry.",
        "overwatering": ["Black stem rot at base", "Yellow leaves", "No flowering"],
        "underwatering": ["Leaf drop (often seasonal and normal)", "Shriveled soft stems", "Slow growth"],
        "hot_season": "Water every 3–5 days. Drought-tolerant once established.",
        "rainy_season": "Reduce to every 6–8 days. Excellent drainage is critical — standing water causes fatal stem rot.",
        "pot_vs_ground": "Ground planting is best. If using a pot, use very sandy mix with no water retention.",
    },
    "ixora coccinea": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels dry.",
        "overwatering": ["Yellow chlorotic leaves", "Root rot", "Reduced flowering"],
        "underwatering": ["Wilting stems", "Brown dry leaf edges", "Flower and bud drop"],
        "hot_season": "Water every 1–2 days. Mulch around base to retain moisture.",
        "rainy_season": "Reduce to every 3–4 days. Ensure free drainage.",
        "pot_vs_ground": "Pot: check daily in hot weather. In-ground ixoras are very adaptable once established.",
    },
    "jasminum sambac": {
        "finger_test": "Insert finger 2–3 cm. Water when the top feels dry.",
        "overwatering": ["Yellow leaves", "Reduced flowering", "Soggy soil smell", "Root rot"],
        "underwatering": ["Wilting", "Poor flowering", "Dry crispy tips on leaves"],
        "hot_season": "Water every 1–2 days. Water at the base — avoid wetting the flowers.",
        "rainy_season": "Reduce to every 3–4 days. Good air circulation prevents fungal issues.",
        "pot_vs_ground": "Both work well. Ground plants need less frequent watering once established.",
    },
    "rosa": {
        "finger_test": "Insert finger 3–4 cm. Water when top feels dry.",
        "overwatering": ["Black spot fungal disease on leaves", "Yellow leaves", "Root rot"],
        "underwatering": ["Wilting", "Smaller or fewer blooms", "Brown crispy leaf edges"],
        "hot_season": "Water every 1–2 days. Water at the base, avoid wetting leaves. Apply mulch.",
        "rainy_season": "Reduce watering. Ensure good drainage. Watch closely for fungal leaf disease.",
        "pot_vs_ground": "Ground gives best performance. Pot roses need more frequent watering and fertilising.",
    },
    "murraya koenigii": {
        "finger_test": "Insert finger 3 cm. Water when top feels slightly dry.",
        "overwatering": ["Yellow leaves", "Root rot", "Leaf drop"],
        "underwatering": ["Dry crispy leaf edges", "Leaf curl", "Very slow growth"],
        "hot_season": "Water every 2–3 days. Fertilise monthly to sustain leaf production.",
        "rainy_season": "Reduce to every 4–5 days. Check that pot drains freely.",
        "pot_vs_ground": "Performs well in both. In-ground plants need less frequent watering once established.",
    },
    "monstera deliciosa": {
        "finger_test": "Insert finger 3–4 cm. Water when the top half of soil feels dry.",
        "overwatering": ["Yellow leaves", "Mushy stems", "Root rot", "Soggy soil smell"],
        "underwatering": ["Droopy curling leaves", "Brown crispy leaf edges", "Slow growth"],
        "hot_season": "Water every 4–6 days. Mist leaves in the morning to boost humidity.",
        "rainy_season": "Reduce to every 7–10 days. Check soil moisture before each watering.",
        "pot_vs_ground": "Pot: ensure drainage holes. As a ground cover, check drainage — root rot is the main risk.",
    },
    "epipremnum aureum": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels dry — pothos tolerates neglect better than overwatering.",
        "overwatering": ["Yellow leaves", "Mushy black stems", "Soil smells sour", "Black root tips"],
        "underwatering": ["Wilting and drooping", "Crispy brown tips", "Curling yellowing leaves"],
        "hot_season": "Water every 2–3 days. Mist leaves occasionally to increase humidity.",
        "rainy_season": "Reduce to every 5–7 days. Prioritise drainage over frequency.",
        "pot_vs_ground": "Pot: excellent choice, easy to manage. Ground: spreads vigorously, monitor soil moisture.",
    },
    "aloe barbadensis": {
        "finger_test": "Insert finger 4–5 cm. Water ONLY when completely dry — aloe stores water in its thick leaves.",
        "overwatering": ["Soft translucent or mushy leaves", "Brown rotting base", "Foul soil smell"],
        "underwatering": ["Thin wrinkled leaves", "Brown dry tips", "Leaves lean outward"],
        "hot_season": "Water every 10–14 days. Ensure full soil dry-out between waterings.",
        "rainy_season": "Reduce or pause watering — natural rainfall is usually sufficient. Protect from waterlogging.",
        "pot_vs_ground": "Use well-draining sandy/gritty soil. Pots must have drainage holes — standing water is fatal.",
    },
    "asplenium nidus": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels slightly dry — ferns prefer consistent moisture.",
        "overwatering": ["Yellow leaves", "Black mushy crown centre", "Root rot smell"],
        "underwatering": ["Brown crispy leaf tips", "Drooping fronds", "Shriveled dry crown"],
        "hot_season": "Water every 4–5 days. Mist leaves daily during dry spells to maintain humidity.",
        "rainy_season": "Reduce to every 7–9 days. Ensure pot drains fully — crown rot is a common issue.",
        "pot_vs_ground": "Pot: monitor closely, small pots dry fast. Ground under trees: stays moist naturally.",
    },
    "phalaenopsis": {
        "finger_test": "Lift the pot — it needs water when it feels very light. Check roots: green = moist, grey/white = thirsty.",
        "overwatering": ["Yellow leaves", "Dark brown mushy roots", "Flower drop", "Root rot under media"],
        "underwatering": ["Wrinkled limp leaves", "Silvery shriveled roots", "No new growth or flower spike"],
        "hot_season": "Water every 5–7 days. Ensure roots dry completely between waterings — good airflow is essential.",
        "rainy_season": "Reduce to every 10–14 days. Never let water sit in the crown or flower base.",
        "pot_vs_ground": "Always use clear pots with drainage holes and bark/perlite mix. Never use garden soil.",
    },
    "dracaena trifasciata": {
        "finger_test": "Insert finger 4–5 cm. Water only when completely dry — snake plants thrive on neglect.",
        "overwatering": ["Soft mushy leaf bases", "Yellow or brown leaves", "Foul-smelling soil", "Root rot"],
        "underwatering": ["Slightly wrinkled leaves", "Very slow growth", "Bone-dry soil pulling from pot edges"],
        "hot_season": "Water every 10–14 days. Always verify soil is completely dry before watering.",
        "rainy_season": "Water once a month or less. One of the most drought-tolerant houseplants.",
        "pot_vs_ground": "Best in pots with drainage. In-ground only in very well-drained raised beds.",
    },
    "spathiphyllum wallisii": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels dry — peace lily droops slightly to signal thirst.",
        "overwatering": ["Yellow leaves", "Wilting despite moist soil", "Root rot", "Heavy soggy soil"],
        "underwatering": ["Dramatic drooping (recovers quickly after watering)", "Brown leaf tips", "Dry soil"],
        "hot_season": "Water every 3–4 days. Keep away from direct sun to reduce moisture loss.",
        "rainy_season": "Reduce to every 5–7 days. Peace lily prefers stable indoor conditions.",
        "pot_vs_ground": "Best as an indoor pot plant. Ensure drainage holes — peace lily dislikes waterlogged roots.",
    },
    "gardenia jasminoides": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels dry — gardenias like consistent moisture.",
        "overwatering": ["Yellow leaves", "Bud drop before opening", "Root rot smell"],
        "underwatering": ["Crispy brown leaf edges", "Bud drop", "Dry compact soil"],
        "hot_season": "Water every 2–3 days. Mulch around base. Mist leaves to raise humidity.",
        "rainy_season": "Reduce to every 4–6 days. Monitor for fungal leaf spots.",
        "pot_vs_ground": "Pot: use acidic, well-draining mix. In-ground: excellent drainage essential.",
    },
    "zamioculcas zamiifolia": {
        "finger_test": "Insert finger 4–5 cm. Water only when fully dry — ZZ stores water in underground rhizomes.",
        "overwatering": ["Yellow leaves", "Rotting rhizomes", "Mushy stems at soil level", "Foul smell"],
        "underwatering": ["Wrinkled yellowing leaves", "Leaf drop", "Very slow growth"],
        "hot_season": "Water every 12–16 days. One of the most drought-tolerant indoor plants.",
        "rainy_season": "Water once a month or less.",
        "pot_vs_ground": "Best in pots with excellent drainage. Ideal as an indoor plant.",
    },
    "musa paradisiaca": {
        "finger_test": "Check soil 5 cm deep. Banana needs consistent moisture — never let it dry out completely.",
        "overwatering": ["Yellow outer leaves", "Soft rotting pseudostem at base", "Fungal crown issues"],
        "underwatering": ["Leaf edges curl and brown", "Slow fruit development", "Pale yellow-green colour"],
        "hot_season": "Water every 1–2 days. Water deeply — banana is a heavy feeder and drinker.",
        "rainy_season": "Reduce watering but maintain soil moisture. Ensure drainage to prevent crown rot.",
        "pot_vs_ground": "Ground planting gives best results. Large container (minimum 60L) if potting.",
    },
    "heliconia psittacorum": {
        "finger_test": "Check soil 3–4 cm. Keep consistently moist but not waterlogged.",
        "overwatering": ["Yellowing base leaves", "Soft rotting pseudostems", "Mushy rhizomes"],
        "underwatering": ["Leaf edges curl and brown", "No flowers produced", "Stunted growth"],
        "hot_season": "Water every 2–3 days. Mulch generously to retain moisture.",
        "rainy_season": "Reduce to every 4–5 days. Heliconias love tropical humidity.",
        "pot_vs_ground": "Ground planting is the natural habitat. Pot: needs large container (30L+).",
    },
    "capsicum annuum": {
        "finger_test": "Insert finger 3 cm. Water when the top half feels dry.",
        "overwatering": ["Yellow lower leaves", "Root rot", "Blossom drop", "Soggy soil"],
        "underwatering": ["Wilting in heat", "Small fruit", "Blossom drop", "Crispy leaf edges"],
        "hot_season": "Water every 1–2 days. Consistent moisture improves fruit set and reduces blossom drop.",
        "rainy_season": "Reduce to every 3–4 days. Watch closely for fungal diseases on leaves.",
        "pot_vs_ground": "Pot: minimum 10-litre container, water frequently. Ground: more drought-tolerant once established.",
    },
}

# Common-name aliases for the species rich care lookup
_COMMON_RICH_CARE: dict[str, dict] = {
    "hibiscus": _SPECIES_RICH_CARE["hibiscus rosa-sinensis"],
    "bunga raya": _SPECIES_RICH_CARE["hibiscus rosa-sinensis"],
    "bougainvillea": _SPECIES_RICH_CARE["bougainvillea spectabilis"],
    "bunga kertas": _SPECIES_RICH_CARE["bougainvillea spectabilis"],
    "desert rose": _SPECIES_RICH_CARE["adenium obesum"],
    "adenium": _SPECIES_RICH_CARE["adenium obesum"],
    "frangipani": _SPECIES_RICH_CARE["plumeria rubra"],
    "plumeria": _SPECIES_RICH_CARE["plumeria rubra"],
    "kamboja": _SPECIES_RICH_CARE["plumeria rubra"],
    "ixora": _SPECIES_RICH_CARE["ixora coccinea"],
    "jasmine": _SPECIES_RICH_CARE["jasminum sambac"],
    "bunga melur": _SPECIES_RICH_CARE["jasminum sambac"],
    "rose": _SPECIES_RICH_CARE["rosa"],
    "mawar": _SPECIES_RICH_CARE["rosa"],
    "curry leaf": _SPECIES_RICH_CARE["murraya koenigii"],
    "daun kari": _SPECIES_RICH_CARE["murraya koenigii"],
    "monstera": _SPECIES_RICH_CARE["monstera deliciosa"],
    "pothos": _SPECIES_RICH_CARE["epipremnum aureum"],
    "money plant": _SPECIES_RICH_CARE["epipremnum aureum"],
    "aloe vera": _SPECIES_RICH_CARE["aloe barbadensis"],
    "aloe": _SPECIES_RICH_CARE["aloe barbadensis"],
    "bird nest fern": _SPECIES_RICH_CARE["asplenium nidus"],
    "asplenium": _SPECIES_RICH_CARE["asplenium nidus"],
    "orchid": _SPECIES_RICH_CARE["phalaenopsis"],
    "phalaenopsis": _SPECIES_RICH_CARE["phalaenopsis"],
    "snake plant": _SPECIES_RICH_CARE["dracaena trifasciata"],
    "sansevieria": _SPECIES_RICH_CARE["dracaena trifasciata"],
    "peace lily": _SPECIES_RICH_CARE["spathiphyllum wallisii"],
    "gardenia": _SPECIES_RICH_CARE["gardenia jasminoides"],
    "zz plant": _SPECIES_RICH_CARE["zamioculcas zamiifolia"],
    "zamioculcas": _SPECIES_RICH_CARE["zamioculcas zamiifolia"],
    "banana": _SPECIES_RICH_CARE["musa paradisiaca"],
    "pisang": _SPECIES_RICH_CARE["musa paradisiaca"],
    "heliconia": _SPECIES_RICH_CARE["heliconia psittacorum"],
    "chili": _SPECIES_RICH_CARE["capsicum annuum"],
    "cili": _SPECIES_RICH_CARE["capsicum annuum"],
    "pepper": _SPECIES_RICH_CARE["capsicum annuum"],
}

# Type-level rich care defaults — used when no species match is found.
_TYPE_RICH_CARE: dict[str, dict] = {
    "succulent": {
        "finger_test": "Insert finger 4–5 cm. Water ONLY when completely dry — succulents store water in their leaves.",
        "overwatering": ["Soft translucent or mushy leaves", "Rotting stem base", "Foul-smelling soil"],
        "underwatering": ["Thin wrinkled or puckered leaves", "Dry soil pulling from pot edges"],
        "hot_season": "Water every 10–14 days. Always allow full dry-out. Morning watering preferred.",
        "rainy_season": "Reduce to every 14–21 days. Protect from prolonged waterlogging.",
        "pot_vs_ground": "Use fast-draining gritty/sandy mix. Drainage holes are essential — standing water is fatal.",
    },
    "cactus": {
        "finger_test": "Insert finger 5 cm or use a wooden skewer. Water only when bone-dry.",
        "overwatering": ["Soft mushy body or base", "Yellow or brown discoloration", "Falling or limp spines"],
        "underwatering": ["Wrinkled or shrunken stem", "Dull flat appearance"],
        "hot_season": "Water every 14–21 days. Full dry-out is essential.",
        "rainy_season": "Water every 21–30 days or less. Protect from excess rainfall.",
        "pot_vs_ground": "Use cactus/sand mix with drainage holes. Avoid heavy garden soil.",
    },
    "fern": {
        "finger_test": "Insert finger 2–3 cm. Water when the top feels slightly dry — ferns prefer consistent moisture.",
        "overwatering": ["Yellow leaves", "Black or brown mushy crown", "Root rot smell"],
        "underwatering": ["Brown crispy leaf tips", "Drooping or wilting fronds", "Dry compact soil"],
        "hot_season": "Water every 3–5 days. Mist leaves daily in hot dry spells.",
        "rainy_season": "Reduce to every 6–9 days. Ensure free drainage.",
        "pot_vs_ground": "Pot: dries out faster, needs regular monitoring. Ground under trees: stays naturally moist.",
    },
    "orchid": {
        "finger_test": "Lift the pot — water when it feels very light. Check roots: white/grey = thirsty, green = moist.",
        "overwatering": ["Dark mushy roots", "Yellow limp leaves", "Flower drop"],
        "underwatering": ["Silvery wrinkled roots", "Limp leaves", "No new growth or flower spike"],
        "hot_season": "Water every 5–7 days. Roots must dry between waterings.",
        "rainy_season": "Water every 10–14 days. Never let water sit in crown. Good airflow is critical.",
        "pot_vs_ground": "Always use clear pots with bark/perlite mix and drainage holes. Never use garden soil.",
    },
    "herb": {
        "finger_test": "Insert finger 2–3 cm. Water when top feels dry — most herbs prefer evenly moist soil.",
        "overwatering": ["Yellow lower leaves", "Wilting despite moist soil", "Root rot", "Fungal stem issues"],
        "underwatering": ["Wilting and drooping", "Dry crispy leaf edges", "Slow growth"],
        "hot_season": "Water every 1–2 days. Harvest regularly to encourage bushy growth.",
        "rainy_season": "Reduce to every 3–4 days. Ensure good drainage to prevent fungal disease.",
        "pot_vs_ground": "Pot: water more frequently, small pots dry fast. Ground: moderate consistent watering.",
    },
    "vegetable": {
        "finger_test": "Insert finger 3 cm. Water when the top half feels dry — consistency matters for good yield.",
        "overwatering": ["Yellow leaves", "Root rot", "Blossom drop", "Fungal diseases"],
        "underwatering": ["Wilting", "Small or bitter fruit", "Blossom drop", "Slow growth"],
        "hot_season": "Water every 1–2 days. Early morning watering reduces evaporation and disease risk.",
        "rainy_season": "Reduce to every 2–3 days. Monitor for fungal diseases common in wet weather.",
        "pot_vs_ground": "Pot: water frequently, minimum 15-litre container for fruiting crops. Ground: water deeply.",
    },
    "flower": {
        "finger_test": "Insert finger 2–3 cm. Water when the top feels dry.",
        "overwatering": ["Yellow leaves", "Bud or flower drop", "Root rot", "Wilting despite wet soil"],
        "underwatering": ["Wilting", "Bud drop", "Dry crispy leaf edges"],
        "hot_season": "Water every 1–2 days. Water at the base to keep leaves dry.",
        "rainy_season": "Reduce to every 3–4 days. Ensure good drainage.",
        "pot_vs_ground": "Pot: check daily in hot weather. Ground: generally less maintenance once established.",
    },
    "shrub": {
        "finger_test": "Insert finger 3 cm. Water when the top feels dry.",
        "overwatering": ["Yellow leaves", "Root rot", "Reduced flowering"],
        "underwatering": ["Wilting", "Brown dry leaf edges", "Slow growth"],
        "hot_season": "Water every 1–3 days depending on sun exposure. Mulch to retain moisture.",
        "rainy_season": "Reduce to every 3–5 days. Established shrubs handle rain well.",
        "pot_vs_ground": "Ground is generally preferred for shrubs. Pot: use large container, monitor drainage.",
    },
    "tree": {
        "finger_test": "Check soil 5 cm deep near the root zone. Water when top layer feels dry.",
        "overwatering": ["Yellow leaves", "Root rot", "Fungal bark diseases", "Wilting despite wet soil"],
        "underwatering": ["Leaf drop", "Brown crispy leaves", "Slow or no new growth"],
        "hot_season": "Young trees: water every 2–4 days. Established trees: every 5–7 days.",
        "rainy_season": "Reduce or pause for established trees. Young trees: every 5–7 days.",
        "pot_vs_ground": "Ground planting gives best long-term results. Pot trees need more frequent watering.",
    },
    "vine": {
        "finger_test": "Insert finger 2–3 cm. Water when the top feels dry.",
        "overwatering": ["Yellow leaves", "Root rot", "Reduced flowering or fruiting"],
        "underwatering": ["Wilting tendrils", "Leaf drop", "Poor flowering"],
        "hot_season": "Water every 1–3 days. Vines in full sun dry out quickly.",
        "rainy_season": "Reduce to every 3–5 days. Ensure drainage at the root zone.",
        "pot_vs_ground": "Ground gives best vigour. Pot: large container needed with regular watering.",
    },
    "palm": {
        "finger_test": "Check soil 5 cm deep. Water when the top feels dry — palms tolerate some drought.",
        "overwatering": ["Yellow fronds", "Root rot", "Trunk rot at base"],
        "underwatering": ["Brown dry frond tips", "Drooping older fronds", "Slow new growth"],
        "hot_season": "Water every 3–5 days. Deep watering encourages strong root growth.",
        "rainy_season": "Reduce to every 7–10 days. Most Malaysian palms love natural rainfall.",
        "pot_vs_ground": "Ground: best for large palms. Pot: works for smaller palms with good drainage.",
    },
    "other": {
        "finger_test": "Insert finger 2–3 cm into soil. Water when the top layer feels dry.",
        "overwatering": ["Yellow leaves", "Wilting despite moist soil", "Root rot smell from soil"],
        "underwatering": ["Wilting or drooping", "Dry crispy leaf edges", "Bone-dry soil"],
        "hot_season": "Water at the more frequent end of the recommended range. Check soil every 1–2 days.",
        "rainy_season": "Reduce frequency and always check soil moisture before watering.",
        "pot_vs_ground": "Pots dry out faster than ground beds. Check pot plants more frequently in hot weather.",
    },
}


def _lookup_rich_care(
    scientific_name: str | None,
    common_name:     str | None,
    plant_type:      str | None,
) -> dict:
    """Return rich watering care data for a plant.

    Priority: species by scientific name → species by common name → plant type → default.
    """
    # 1. Species match by scientific name
    if scientific_name:
        sci = scientific_name.lower().strip()
        for key in _SPECIES_RICH_CARE:
            if sci == key or sci.startswith(key.split()[0] + " ") or sci == key.split()[0]:
                return _SPECIES_RICH_CARE[key]
    # 2. Common name match
    if common_name:
        cn = common_name.lower().strip()
        if cn in _COMMON_RICH_CARE:
            return _COMMON_RICH_CARE[cn]
        for key in _COMMON_RICH_CARE:
            if key in cn or cn in key:
                return _COMMON_RICH_CARE[key]
    # 3. Plant type fallback
    pt = (plant_type or "").lower().strip()
    for key in _TYPE_RICH_CARE:
        if key in pt:
            return _TYPE_RICH_CARE[key]
    return _TYPE_RICH_CARE["other"]


# Plant-type-aware clamping for AI-parsed watering text.
# Prevents "daily" AI advice from setting a shrub to 1 day,
# and "fortnightly" advice from making a vegetable wait 14 days.
# Format: (min_days, max_days)
_WATERING_TYPE_BOUNDS: dict[str, tuple[int, int]] = {
    "succulent":  (7,  30),
    "cactus":     (10, 30),
    "flower":     (1,  5),
    "shrub":      (2,  7),
    "tree":       (2,  10),
    "vegetable":  (1,  4),
    "herb":       (1,  3),
    "vine":       (1,  5),
    "grass":      (2,  5),
    "other":      (1,  7),
}


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
    Return watering reminder interval in days. Always returns a positive integer.

    Priority:
      1. Species-specific database (watering_days field)
      2. AI watering text — clamped by plant-type bounds to prevent bad values
      3. Plant-type fallback
    """
    # 1. Species override
    species = _lookup_species(scientific_name, plant_name)
    if species and "watering_days" in species:
        return max(1, species["watering_days"])

    pt = (plant_type or "").lower().strip()
    bounds = _WATERING_TYPE_BOUNDS.get(pt, (1, 7))

    # 2. AI watering text — apply type-aware bounds
    if details_json:
        try:
            data = json.loads(details_json)
            watering_text = (
                data.get("growing", {}).get("watering") or
                data.get("growing", {}).get("water") or ""
            )
            days = _text_to_days(watering_text)
            if days is not None:
                clamped = max(bounds[0], min(bounds[1], days))
                if clamped != days:
                    print(f"[watering] AI parsed {days}d clamped to {clamped}d (type={pt!r}, bounds={bounds})")
                return clamped
        except (json.JSONDecodeError, AttributeError):
            pass

    # 3. Plant-type fallback
    return _WATERING_DEFAULTS.get(pt, _WATERING_DEFAULT)


def get_watering_recommendation(
    details_json:    str | None,
    plant_type:      str | None,
    plant_name:      str | None = None,
    scientific_name: str | None = None,
) -> dict:
    """
    Return a watering recommendation with a human-readable range and rich
    care intelligence (finger test, symptom signs, seasonal guidance).

    Returns:
        {
          "interval":       int,
          "pot_range":      "1-2",
          "ground_range":   "2-3",
          "display":        "Every 1–2 days (pot) · 2–3 days (ground)",
          "source":         str,           # species_specific | ai_estimated | plant_type_rule
          "finger_test":    str,           # how to check soil moisture
          "overwatering":   list[str],     # visible symptoms of overwatering
          "underwatering":  list[str],     # visible symptoms of underwatering
          "hot_season":     str,           # Malaysia hot/dry season adjustment
          "rainy_season":   str,           # Malaysia monsoon season adjustment
          "pot_vs_ground":  str,           # key pot vs in-ground differences
        }
    """
    pt = (plant_type or "").lower().strip()
    rich = _lookup_rich_care(scientific_name, plant_name, plant_type)

    def _build(interval, pot_range, gnd_range, source) -> dict:
        display = f"Every {pot_range} days"
        if gnd_range:
            display += f" (pot) · {gnd_range} days (ground)"
        else:
            display += " (pot)"
        return {
            "interval":      interval,
            "pot_range":     pot_range,
            "ground_range":  gnd_range,
            "display":       display,
            "source":        source,
            "finger_test":   rich.get("finger_test", ""),
            "overwatering":  rich.get("overwatering", []),
            "underwatering": rich.get("underwatering", []),
            "hot_season":    rich.get("hot_season", ""),
            "rainy_season":  rich.get("rainy_season", ""),
            "pot_vs_ground": rich.get("pot_vs_ground", ""),
        }

    # 1. Species override
    species = _lookup_species(scientific_name, plant_name)
    if species:
        interval  = max(1, species["watering_days"])
        pot_range = species.get("watering_range", str(interval))
        gnd_range = species.get("watering_ground")
        return _build(interval, pot_range, gnd_range, SOURCE_SPECIES)

    bounds    = _WATERING_TYPE_BOUNDS.get(pt, (1, 7))
    pot_range = _WATERING_DEFAULTS_RANGE.get(pt, "2-3")
    gnd_range = _WATERING_GROUND_RANGE.get(pt, "3-5")

    # 2. AI watering text — generate interval but keep type-range for display
    if details_json:
        try:
            data = json.loads(details_json)
            watering_text = (
                data.get("growing", {}).get("watering") or
                data.get("growing", {}).get("water") or ""
            )
            days = _text_to_days(watering_text)
            if days is not None:
                interval = max(bounds[0], min(bounds[1], days))
                if interval == 1:
                    ai_pot_range = "1-2"
                else:
                    ai_pot_range = f"{max(1, interval-1)}-{interval+1}"
                return _build(interval, ai_pot_range, gnd_range, SOURCE_AI)
        except (json.JSONDecodeError, AttributeError):
            pass

    # 3. Type fallback
    interval = _WATERING_DEFAULTS.get(pt, _WATERING_DEFAULT)
    return _build(interval, pot_range, gnd_range, SOURCE_TYPE)
