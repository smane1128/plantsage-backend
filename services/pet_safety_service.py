"""
Pet safety knowledge base for Malaysian garden plants.

Priority when determining pet safety:
    1. This database (authoritative, curated)
    2. AI response (fallback — stored as "ai" source)
    3. Unknown (shown as "Pet safety information unavailable")

Status values:
    "safe"    — 🟢 No significant risk to cats/dogs
    "caution" — 🟡 Mild irritant; monitor pet exposure
    "toxic"   — 🔴 Genuinely toxic; keep pets away
    "unknown" — ⚪ Not in database; use AI estimate or unknown

Each entry (keyed by scientific name, lowercase):
    status           safe | caution | toxic
    toxicity_level   None | Mild | Moderate | High
    affected_animals e.g. "Cats, Dogs" or "All pets"
    symptoms         Short description of adverse effects
"""
from __future__ import annotations

# ─── Primary lookup table (scientific name → safety info) ────────────────────
_SAFETY: dict[str, dict] = {
    # ── Genus-level fallback entries (matched when exact species not found) ────
    # These catch any Rosa sp., Hibiscus sp., etc. regardless of AI naming.
    "rosa": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Generally non-toxic to cats and dogs. Take care around thorns.",
    },
    "hibiscus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Safe for cats and dogs. May cause mild stomach upset if eaten in large quantities.",
    },
    "jasminum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Non-toxic to cats and dogs.",
    },
    "ixora": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Non-toxic to cats and dogs.",
    },
    "plumeria": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Milky sap may cause mild skin or oral irritation if ingested.",
    },
    "bougainvillea": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Generally non-toxic, but thorns and sap may cause skin and oral irritation.",
    },
    "allamanda": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "May cause vomiting and stomach irritation if ingested. All parts contain toxic glycosides.",
    },
    "nerium": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Cardiac arrhythmia, vomiting, drooling — all parts toxic; veterinary emergency.",
    },
    "adenium": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Cardiac glycosides — heart rhythm disturbances, vomiting; all parts toxic.",
    },

    # ── Safe plants ──────────────────────────────────────────────────────────
    "rosa spp.": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Generally non-toxic to cats and dogs. Take care around thorns.",
    },
    "rosa indica": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Generally non-toxic to cats and dogs. Take care around thorns.",
    },
    "rosa damascena": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Generally non-toxic to cats and dogs. Take care around thorns.",
    },
    "helianthus annuus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "jasminum sambac": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Non-toxic to cats and dogs.",
    },
    "hibiscus rosa-sinensis": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Safe for cats and dogs. May cause mild stomach upset if eaten in large quantities.",
    },
    "hibiscus sabdariffa": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "nelumbo nucifera": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "nymphaea sp.": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "cymbopogon citratus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "pandanus amaryllifolius": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "psidium guajava": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "carica papaya": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "musa paradisiaca": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "musa acuminata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "mangifera indica": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "peltophorum pterocarpum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "tabebuia rosea": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "samanea saman": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "heliconia psittacorum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "pyrostegia venusta": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "antigonon leptopus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "pentas lanceolata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "ixora coccinea": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "ocimum basilicum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "salvia rosmarinus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "thunbergia grandiflora": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "sphagneticola trilobata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "evolvulus glomeratus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "portulaca grandiflora": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "combretum indicum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "tecoma stans": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "mussaenda philippica": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "citrus aurantifolia": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "barleria cristata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "",
    },
    "jasminum multiflorum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "",
        "symptoms": "Non-toxic to cats and dogs.",
    },

    # ── Plumeria / Frangipani ──────────────────────────────────────────────────
    "plumeria rubra": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Milky sap may cause mild skin or oral irritation if ingested.",
    },
    "plumeria obtusa": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Milky sap may cause mild skin or oral irritation if ingested.",
    },
    "bougainvillea spectabilis": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Generally non-toxic, but thorns and sap may cause skin and oral irritation.",
    },
    "bougainvillea glabra": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Generally non-toxic, but thorns and sap may cause skin and oral irritation.",
    },
    "plumbago auriculata": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild skin and eye irritation on contact",
    },
    "mandevilla sanderi": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild GI irritation if ingested",
    },
    "aloe barbadensis miller": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Vomiting, diarrhea if gel/latex ingested; avoid large amounts",
    },
    "epipremnum aureum": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Oral irritation, drooling, vomiting (calcium oxalate crystals)",
    },
    "spathiphyllum wallisii": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Oral irritation, drooling, vomiting (calcium oxalate crystals)",
    },
    "dracaena trifasciata": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Nausea, vomiting, drooling (saponins)",
    },
    "gardenia jasminoides": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild vomiting, diarrhea if large amounts ingested",
    },
    "strelitzia reginae": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild nausea and drowsiness if ingested",
    },
    "ficus benjamina": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Skin and oral irritation from latex sap; GI upset if ingested",
    },

    # ── Toxic plants ─────────────────────────────────────────────────────────
    "nerium oleander": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Cardiac arrhythmia, vomiting, drooling — all parts toxic; veterinary emergency",
    },
    "adenium obesum": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Cardiac glycosides — heart rhythm disturbances, vomiting; all parts toxic",
    },
    "euphorbia milii": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Latex sap causes vomiting, diarrhea, skin/eye irritation",
    },
    "allamanda cathartica": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "May cause vomiting and stomach irritation if ingested. All parts contain toxic glycosides.",
    },
    "duranta erecta": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Berries cause vomiting, diarrhea, drowsiness",
    },
    "lantana camara": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Liver damage, photosensitivity, lethargy — berries especially dangerous",
    },
    "catharanthus roseus": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Vinca alkaloids — severe vomiting, neurological effects, hypotension",
    },
    "gloriosa superba": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Colchicine toxicity — severe GI distress, multi-organ failure; all parts toxic",
    },
    "caladium spp.": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Intense oral irritation, swelling, drooling, difficulty swallowing (calcium oxalate)",
    },
    "dieffenbachia spp.": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Intense oral burning, swelling, excessive drooling (calcium oxalate crystals)",
    },
    "philodendron spp.": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Oral irritation, drooling, vomiting (calcium oxalate crystals)",
    },

    # ── High-priority Malaysian garden additions ───────────────────────────
    # Cycas / Sago palm — CRITICAL: cycasin causes fatal liver failure
    "cycas": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Cycasin toxin — severe liver failure, neurological damage, seizures. ALL parts toxic; seeds most dangerous. Veterinary emergency.",
    },
    "cycas revoluta": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Cycasin toxin — severe liver failure, neurological damage, seizures. ALL parts toxic; seeds most dangerous. Veterinary emergency.",
    },
    "zamia": {
        "status": "toxic", "toxicity_level": "High",
        "affected_animals": "All pets",
        "symptoms": "Cycasin toxin (sago palm family) — liver failure, neurological effects.",
    },
    # Monstera
    "monstera": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — intense oral irritation, drooling, vomiting if chewed.",
    },
    "monstera deliciosa": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — intense oral irritation, drooling, vomiting if chewed.",
    },
    # Aglaonema / Chinese evergreen
    "aglaonema": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral irritation, drooling, vomiting.",
    },
    # Anthurium
    "anthurium": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral irritation, swelling, excessive drooling.",
    },
    # ZZ Plant
    "zamioculcas": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate — mild oral irritation and vomiting if ingested.",
    },
    "zamioculcas zamiifolia": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate — mild oral irritation and vomiting if ingested.",
    },
    # Codiaeum / Croton
    "codiaeum": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Latex sap — skin irritation, vomiting, diarrhea if ingested.",
    },
    "codiaeum variegatum": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Latex sap — skin irritation, vomiting, diarrhea if ingested.",
    },
    # Euphorbia genus (pencil cactus, milk bush, poinsettia, etc.)
    "euphorbia": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Milky latex sap — mucous membrane/skin irritation, vomiting, diarrhea, eye irritation.",
    },
    # Orchid family — all non-toxic
    "dendrobium": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "phalaenopsis": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "vanda": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "oncidium": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Crossandra / Firecracker flower — safe
    "crossandra": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "crossandra infundibuliformis": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Queen of the Night (cactus family — safe)
    "selenicereus": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "epiphyllum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Crocus — spring crocus mild; autumn crocus (Colchicum) highly toxic
    "crocus": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "May cause stomach upset if chewed or ingested. Keep away from cats and dogs. Note: Autumn crocus (Colchicum) is far more toxic — verify species.",
    },
    # Syngonium / arrowhead vine
    "syngonium": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral irritation, drooling, vomiting.",
    },
    # Schefflera / umbrella plant
    "schefflera": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Terpenoids and calcium oxalate — vomiting, oral irritation, drooling.",
    },
    # Acalypha / Jacob's coat
    "acalypha": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild skin and GI irritation from sap if ingested.",
    },
    # Begonia
    "begonia": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Soluble calcium oxalates especially in tubers — salivation, vomiting.",
    },
    # Impatiens / busy lizzie — safe
    "impatiens": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Ruellia / Mexican petunia — safe
    "ruellia": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Narcissus / Daffodil — toxic (lycorine alkaloids)
    "narcissus": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Lycorine alkaloids — vomiting, diarrhea, hypotension, drooling. Bulbs most toxic.",
    },
    "narcissus pseudonarcissus": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Lycorine alkaloids — vomiting, diarrhea, hypotension, drooling. Bulbs most toxic.",
    },
    # Tulipa / Tulip — toxic (tulipalin A & B)
    "tulipa": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Tulipalin A & B — intense vomiting, depression, diarrhea. Bulbs most concentrated.",
    },
    "tulipa gesneriana": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Tulipalin A & B — intense vomiting, depression, diarrhea. Bulbs most concentrated.",
    },
    # Hyacinthus / Hyacinth — toxic (narcissiine alkaloids)
    "hyacinthus": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Alkaloids in bulbs — vomiting, diarrhea, drooling, tremors. Bulb handling may cause contact dermatitis.",
    },
    "hyacinthus orientalis": {
        "status": "toxic", "toxicity_level": "Moderate",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Alkaloids in bulbs — vomiting, diarrhea, drooling, tremors. Bulb handling may cause contact dermatitis.",
    },
    # Calathea — safe (prayer plant family)
    "calathea": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Maranta — safe (prayer plant)
    "maranta": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Chlorophytum / spider plant — safe
    "chlorophytum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "chlorophytum comosum": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Saintpaulia / African violet — safe
    "saintpaulia": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Nephrolepis / Boston fern — safe
    "nephrolepis": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "nephrolepis exaltata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    # Ficus elastica / rubber plant — caution (latex sap)
    "ficus elastica": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Latex sap may cause skin and oral irritation, mild GI upset if large amounts ingested.",
    },
    # Crassula / jade plant — caution
    "crassula": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Vomiting, depression, ataxia if ingested (mechanism unknown).",
    },
    "crassula ovata": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Vomiting, depression, ataxia if ingested (mechanism unknown).",
    },
    # Muscari / grape hyacinth — caution
    "muscari": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Mild GI irritation — vomiting and diarrhea if bulbs ingested.",
    },
    # Colocasia / taro / keladi
    "colocasia": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral and GI irritation, drooling.",
    },

    # ── Alocasia / Giant Taro / Elephant Ear ────────────────────────────────
    "alocasia": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — intense oral and GI irritation, drooling, swelling of mouth/throat if chewed.",
    },
    "alocasia macrorrhizos": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — intense oral and GI irritation, drooling, swelling of mouth/throat if chewed.",
    },
    "alocasia odora": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral irritation, drooling, vomiting.",
    },
    "alocasia amazonica": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Calcium oxalate crystals — oral irritation, drooling, vomiting.",
    },

    # ── Cordyline / Ti Plant ─────────────────────────────────────────────────
    "cordyline": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Saponins — vomiting (possibly with blood), depression, loss of appetite. More pronounced in cats.",
    },
    "cordyline fruticosa": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Saponins — vomiting (possibly with blood), depression, loss of appetite. More pronounced in cats.",
    },
    "cordyline terminalis": {
        "status": "caution", "toxicity_level": "Mild",
        "affected_animals": "Cats, Dogs",
        "symptoms": "Saponins — vomiting (possibly with blood), depression, loss of appetite.",
    },

    # ── Canna Lily ───────────────────────────────────────────────────────────
    "canna": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "canna indica": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "canna generalis": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },

    # ── Ginger family ────────────────────────────────────────────────────────
    "zingiber": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "zingiber officinale": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "curcuma": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "curcuma longa": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "alpinia": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "alpinia purpurata": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "alpinia galanga": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "etlingera": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
    "etlingera elatior": {
        "status": "safe", "toxicity_level": "None",
        "affected_animals": "", "symptoms": "Non-toxic to cats and dogs.",
    },
}

# ─── Common name aliases → scientific name (lowercase) ───────────────────────
# Used when the scientific name lookup fails.
_ALIASES: dict[str, str] = {
    # Safe
    "rose":               "rosa spp.",
    "sunflower":          "helianthus annuus",
    "jasmine sambac":     "jasminum sambac",
    "bunga melur":        "jasminum sambac",
    "jasmine":            "jasminum sambac",
    "hibiscus":           "hibiscus rosa-sinensis",
    "bunga raya":         "hibiscus rosa-sinensis",
    "lotus":              "nelumbo nucifera",
    "water lily":         "nymphaea sp.",
    "lemongrass":         "cymbopogon citratus",
    "serai":              "cymbopogon citratus",
    "pandan":             "pandanus amaryllifolius",
    "guava":              "psidium guajava",
    "papaya":             "carica papaya",
    "banana":             "musa paradisiaca",
    "mango":              "mangifera indica",
    "yellow flame tree":  "peltophorum pterocarpum",
    "pink trumpet tree":  "tabebuia rosea",
    "rain tree":          "samanea saman",
    "heliconia":          "heliconia psittacorum",
    "flame vine":         "pyrostegia venusta",
    "coral vine":         "antigonon leptopus",
    "pentas":             "pentas lanceolata",
    "ixora":              "ixora coccinea",
    "basil":              "ocimum basilicum",
    "rosemary":           "salvia rosmarinus",
    "blue trumpet vine":  "thunbergia grandiflora",
    "wedelia":            "sphagneticola trilobata",
    "blue daze":          "evolvulus glomeratus",
    "portulaca":          "portulaca grandiflora",
    "rangoon creeper":    "combretum indicum",
    "yellow bells":       "tecoma stans",
    "mussaenda":          "mussaenda philippica",
    "lime":               "citrus aurantifolia",
    "barleria":           "barleria cristata",
    "star jasmine":       "jasminum multiflorum",
    # Caution
    "bougainvillea":      "bougainvillea spectabilis",
    "plumbago":           "plumbago auriculata",
    "mandevilla":         "mandevilla sanderi",
    "aloe vera":          "aloe barbadensis miller",
    "aloe":               "aloe barbadensis miller",
    "pothos":             "epipremnum aureum",
    "golden pothos":      "epipremnum aureum",
    "peace lily":         "spathiphyllum wallisii",
    "snake plant":        "dracaena trifasciata",
    "mother-in-law tongue": "dracaena trifasciata",
    "gardenia":           "gardenia jasminoides",
    "bird of paradise":   "strelitzia reginae",
    "weeping fig":        "ficus benjamina",
    "ficus":              "ficus benjamina",
    "plumeria":           "plumeria rubra",
    "frangipani":         "plumeria rubra",
    "kemboja":            "plumeria rubra",
    # Toxic
    "oleander":           "nerium oleander",
    "desert rose":        "adenium obesum",
    "crown of thorns":    "euphorbia milii",
    "allamanda":          "allamanda cathartica",
    "golden trumpet":     "allamanda cathartica",
    "golden dewdrop":     "duranta erecta",
    "duranta":            "duranta erecta",
    "lantana":            "lantana camara",
    "periwinkle":         "catharanthus roseus",
    "vinca":              "catharanthus roseus",
    "glory lily":         "gloriosa superba",
    "caladium":           "caladium spp.",
    "dumb cane":          "dieffenbachia spp.",
    "dieffenbachia":      "dieffenbachia spp.",
    "philodendron":       "philodendron spp.",
    # New additions
    "sago palm":             "cycas revoluta",
    "swiss cheese plant":    "monstera deliciosa",
    "chinese evergreen":     "aglaonema",
    "flamingo flower":       "anthurium",
    "zz plant":              "zamioculcas zamiifolia",
    "zanzibar gem":          "zamioculcas zamiifolia",
    "croton":                "codiaeum variegatum",
    "jacob's coat":          "codiaeum variegatum",
    "pencil cactus":         "euphorbia",
    "milk bush":             "euphorbia",
    "poinsettia":            "euphorbia",
    "orchid":                "dendrobium",
    "moth orchid":           "phalaenopsis",
    "firecracker flower":    "crossandra infundibuliformis",
    "queen of the night":    "selenicereus",
    "night blooming cereus": "selenicereus",
    "crocus":                "crocus",
    "arrowhead vine":        "syngonium",
    "umbrella plant":        "schefflera",
    "busy lizzie":           "impatiens",
    "mexican petunia":       "ruellia",
    "taro":                  "colocasia",
    "keladi":                "colocasia",
    "elephant ear":          "colocasia",
    # New aliases — spring bulbs and common names
    "daffodil":              "narcissus",
    "narcissus":             "narcissus",
    "jonquil":               "narcissus",
    "tulip":                 "tulipa",
    "hyacinth":              "hyacinthus",
    "grape hyacinth":        "muscari",
    "calathea":              "calathea",
    "prayer plant":          "maranta",
    "maranta":               "maranta",
    "spider plant":          "chlorophytum comosum",
    "african violet":        "saintpaulia",
    "boston fern":           "nephrolepis exaltata",
    "money plant":           "epipremnum aureum",
    "rubber plant":          "ficus elastica",
    "jade plant":            "crassula ovata",
    # Alocasia
    "alocasia":              "alocasia macrorrhizos",
    "giant taro":            "alocasia macrorrhizos",
    "giant elephant ear":    "alocasia macrorrhizos",
    "african mask":          "alocasia amazonica",
    "jewel alocasia":        "alocasia amazonica",
    # Cordyline
    "ti plant":              "cordyline fruticosa",
    "good luck plant":       "cordyline fruticosa",
    "red ti":                "cordyline fruticosa",
    "cordyline":             "cordyline fruticosa",
    # Canna
    "canna lily":            "canna indica",
    "canna":                 "canna indica",
    # Ginger family
    "ginger":                "zingiber officinale",
    "halia":                 "zingiber officinale",
    "turmeric":              "curcuma longa",
    "kunyit":                "curcuma longa",
    "torch ginger":          "etlingera elatior",
    "bunga kantan":          "etlingera elatior",
    "galangal":              "alpinia galanga",
    "lengkuas":              "alpinia galanga",
    "red ginger":            "alpinia purpurata",
}


def lookup_pet_safety(scientific_name: str, common_name: str) -> dict:
    """Return pet safety info for the given plant.

    Lookup order:
        1. scientific_name exact match (case-insensitive)
        2. scientific_name genus exact (e.g. "Rosa" → "rosa")
        3. scientific_name genus + " spp." (e.g. "Rosa hybrida" → "rosa spp.")
        4. common_name alias (exact)
        5. common_name partial match
        Returns status="unknown" if nothing matches.

    Returns:
        {status, toxicity_level, affected_animals, symptoms, source}
        source is always "database" when found, "unknown" otherwise.
    """
    def _make(entry: dict, matched_key: str) -> dict:
        print(f"[pet_safety] MATCH '{matched_key}' → status={entry['status']}")
        return {
            "status":           entry["status"],
            "toxicity_level":   entry.get("toxicity_level", ""),
            "affected_animals": entry.get("affected_animals", ""),
            "symptoms":         entry.get("symptoms", ""),
            "source":           "database",
        }

    sci = (scientific_name or "").strip().lower()
    com = (common_name or "").strip().lower()

    print(f"[pet_safety] lookup → sci='{sci}' com='{com}'")

    # 1. Exact scientific name match
    if sci and sci in _SAFETY:
        return _make(_SAFETY[sci], f"exact:{sci}")

    # 2. Genus-only key (e.g. "Rosa" → "rosa", "Rosa hybrida" → "rosa")
    if sci:
        genus = sci.split()[0]
        # Strip any hybrid/author markers from genus (×, ×, L., etc.)
        genus = genus.strip("××.,'\"")
        if genus and genus in _SAFETY:
            return _make(_SAFETY[genus], f"genus:{genus}")

        # 3. Genus + " spp." (legacy entries)
        genus_spp = f"{genus} spp."
        if genus_spp in _SAFETY:
            return _make(_SAFETY[genus_spp], f"genus_spp:{genus_spp}")

    # 4. Common name alias (exact)
    if com and com in _ALIASES:
        sci_alias = _ALIASES[com]
        if sci_alias in _SAFETY:
            return _make(_SAFETY[sci_alias], f"alias_exact:{com}")
        # Also check if the alias is itself a genus key
        genus_alias = sci_alias.split()[0] if " " in sci_alias else sci_alias
        if genus_alias in _SAFETY:
            return _make(_SAFETY[genus_alias], f"alias_genus:{genus_alias}")

    # 5. Partial common name match (e.g. "Pink Bougainvillea" → "bougainvillea")
    if com:
        for alias_key, sci_alias in _ALIASES.items():
            if alias_key in com or com in alias_key:
                if sci_alias in _SAFETY:
                    return _make(_SAFETY[sci_alias], f"partial:{alias_key}")
                genus_alias = sci_alias.split()[0] if " " in sci_alias else sci_alias
                if genus_alias in _SAFETY:
                    return _make(_SAFETY[genus_alias], f"partial_genus:{genus_alias}")

    print(f"[pet_safety] NO MATCH for sci='{sci}' com='{com}' → unknown")
    return {
        "status":           "unknown",
        "toxicity_level":   "",
        "affected_animals": "",
        "symptoms":         "",
        "source":           "unknown",
    }
