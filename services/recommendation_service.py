"""
Similarity-based plant recommendation engine for Malaysian gardens.

Scoring weights (v2):
    Plant Category   30%
    Landscape Use    20%
    Growth Habit     20%
    Sunlight         10%
    Water            10%
    Maintenance       5%
    Flowering         5%

Knowledge base: 150+ plants commonly available in Malaysian nurseries.
All recommendations are tropical-climate compatible.
"""
from __future__ import annotations
import re as _re

# --- Categories ---
CAT_FLOWERING_SHRUB    = "Flowering Shrub"
CAT_FLOWERING_VINE     = "Flowering Vine"
CAT_INDOOR_FOLIAGE     = "Indoor Foliage"
CAT_SUCCULENT          = "Succulent"
CAT_PALM               = "Palm"
CAT_ORCHID             = "Orchid"
CAT_GROUNDCOVER        = "Groundcover"
CAT_TREE               = "Tree"
CAT_TROPICAL_FLOWERING = "Tropical Flowering Plant"
CAT_HERB               = "Herb"
CAT_FRUIT              = "Fruit"
CAT_AQUATIC            = "Aquatic"
CAT_GRASS              = "Grass"
CAT_FERN               = "Fern"

# --- Knowledge base ---
# Each entry:
#   category    one of CAT_* constants
#   sunlight    "full_sun" | "partial_shade" | "full_shade"
#   water       "low" | "medium" | "high"
#   habit       "vine" | "shrub" | "tree" | "herb" | "groundcover" |
#               "succulent" | "aquatic" | "grass" | "palm" | "fern"
#   landscape   list of use-case labels
#   maintenance "easy" | "medium" | "hard"
#   flowering   bool
#   tags        2-3 display tags
_PLANTS: list[dict] = [

    # === FLOWERING VINES ===
    {"name": "Bougainvillea", "scientific_name": "Bougainvillea spectabilis",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "low",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Allamanda", "scientific_name": "Allamanda cathartica",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Climber"]},
    {"name": "Mandevilla", "scientific_name": "Mandevilla sanderi",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Flowering","Climber"]},
    {"name": "Rangoon Creeper", "scientific_name": "Combretum indicum",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","fragrance","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fragrant","Climber"]},
    {"name": "Coral Vine", "scientific_name": "Antigonon leptopus",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "low",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Flame Vine", "scientific_name": "Pyrostegia venusta",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "low",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Blue Trumpet Vine", "scientific_name": "Thunbergia grandiflora",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Climber"]},
    {"name": "Star Jasmine", "scientific_name": "Jasminum multiflorum",
     "category": CAT_FLOWERING_VINE, "sunlight": "partial_shade", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","fragrance"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Fragrant","Climber"]},
    {"name": "Black-eyed Susan Vine", "scientific_name": "Thunbergia alata",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Climber"]},
    {"name": "Petrea", "scientific_name": "Petrea volubilis",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Climber"]},
    {"name": "Clerodendrum", "scientific_name": "Clerodendrum thomsoniae",
     "category": CAT_FLOWERING_VINE, "sunlight": "partial_shade", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Climber"]},
    {"name": "Wisteria", "scientific_name": "Wisteria sinensis",
     "category": CAT_FLOWERING_VINE, "sunlight": "full_sun", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","climber","flowering","fragrance"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Fragrant","Climber"]},

    # === FLOWERING SHRUBS - FULL SUN ===
    {"name": "Hibiscus", "scientific_name": "Hibiscus rosa-sinensis",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Ixora", "scientific_name": "Ixora coccinea",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Yellow Bells", "scientific_name": "Tecoma stans",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Plumbago", "scientific_name": "Plumbago auriculata",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Golden Dewdrop", "scientific_name": "Duranta erecta",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Lantana", "scientific_name": "Lantana camara",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Pentas", "scientific_name": "Pentas lanceolata",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Barleria", "scientific_name": "Barleria cristata",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Crossandra", "scientific_name": "Crossandra infundibuliformis",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Easy Care"]},
    {"name": "Ruellia", "scientific_name": "Ruellia simplex",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","groundcover"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Salvia", "scientific_name": "Salvia splendens",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Acalypha", "scientific_name": "Acalypha wilkesiana",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","colorful","hedge","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Colorful Foliage","Hedge"]},
    {"name": "Turks Cap", "scientific_name": "Malvaviscus arboreus",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Easy Care"]},
    {"name": "Firecracker Plant", "scientific_name": "Russelia equisetiformis",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Mexican Heather", "scientific_name": "Cuphea hyssopifolia",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Tibouchina", "scientific_name": "Tibouchina urvilleana",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Flowering","Colorful"]},
    {"name": "Kopsia", "scientific_name": "Kopsia fruticosa",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Fragrant"]},
    {"name": "Brunfelsia", "scientific_name": "Brunfelsia pauciflora",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","colorful"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Fragrant","Flowering"]},
    {"name": "Hamelia", "scientific_name": "Hamelia patens",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Quisqualis", "scientific_name": "Quisqualis indica",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fragrant","Flowering"]},
    {"name": "Tabernaemontana", "scientific_name": "Tabernaemontana divaricata",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Fragrant","Flowering"]},

    # === FLOWERING SHRUBS - PARTIAL SHADE ===
    {"name": "Gardenia", "scientific_name": "Gardenia jasminoides",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","landscaping"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Fragrant","Flowering"]},
    {"name": "Jasmine", "scientific_name": "Jasminum sambac",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Fragrant","Flowering"]},
    {"name": "Mussaenda", "scientific_name": "Mussaenda philippica",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Easy Care"]},
    {"name": "Ixora Dwarf", "scientific_name": "Ixora chinensis",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","hedge"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Hedge"]},
    {"name": "Impatiens", "scientific_name": "Impatiens walleriana",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Colorful"]},
    {"name": "Begonia", "scientific_name": "Begonia cucullata",
     "category": CAT_FLOWERING_SHRUB, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","indoor"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Colorful"]},
    {"name": "Peace Lily", "scientific_name": "Spathiphyllum wallisii",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","flowering"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Shade","Indoor","Flowering"]},

    # === TROPICAL FLOWERING ===
    {"name": "Heliconia", "scientific_name": "Heliconia psittacorum",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Anthurium", "scientific_name": "Anthurium andraeanum",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","indoor","tropical"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Ginger Lily", "scientific_name": "Hedychium coronarium",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Fragrant","Tropical"]},
    {"name": "Torch Ginger", "scientific_name": "Etlingera elatior",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Alpinia", "scientific_name": "Alpinia purpurata",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Costus", "scientific_name": "Costus speciosus",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Medinilla", "scientific_name": "Medinilla magnifica",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Bird of Paradise", "scientific_name": "Strelitzia reginae",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical","landscaping"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Flowering","Tropical"]},
    {"name": "Plumeria", "scientific_name": "Plumeria rubra",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["ornamental","flowering","fragrance","colorful","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fragrant","Tropical"]},
    {"name": "Canna Lily", "scientific_name": "Canna indica",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Tropical"]},
    {"name": "Red Ginger", "scientific_name": "Alpinia purpurata 'Red'",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Tropical"]},
    {"name": "Caladium", "scientific_name": "Caladium bicolor",
     "category": CAT_TROPICAL_FLOWERING, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["ornamental","colorful","tropical","indoor"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Colorful Foliage","Tropical"]},
    {"name": "Desert Rose", "scientific_name": "Adenium obesum",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","flowering","colorful","succulent"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},

    # === ORCHIDS ===
    {"name": "Dendrobium Orchid", "scientific_name": "Dendrobium sp.",
     "category": CAT_ORCHID, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","indoor"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Orchid","Flowering"]},
    {"name": "Phalaenopsis Orchid", "scientific_name": "Phalaenopsis amabilis",
     "category": CAT_ORCHID, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","indoor"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Orchid","Indoor"]},
    {"name": "Vanda Orchid", "scientific_name": "Vanda sp.",
     "category": CAT_ORCHID, "sunlight": "full_sun", "water": "high",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "hard", "flowering": True, "tags": ["Full Sun","Orchid","Flowering"]},
    {"name": "Oncidium Orchid", "scientific_name": "Oncidium sp.",
     "category": CAT_ORCHID, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful","indoor"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Orchid","Flowering"]},
    {"name": "Cattleya Orchid", "scientific_name": "Cattleya sp.",
     "category": CAT_ORCHID, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","fragrance","colorful"],
     "maintenance": "hard", "flowering": True, "tags": ["Partial Shade","Orchid","Fragrant"]},
    {"name": "Aranda Orchid", "scientific_name": "Aranda Noorah Alsagoff",
     "category": CAT_ORCHID, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Orchid","Flowering"]},
    {"name": "Spathoglottis Orchid", "scientific_name": "Spathoglottis plicata",
     "category": CAT_ORCHID, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Orchid","Easy Care"]},

    # === PALMS ===
    {"name": "Areca Palm", "scientific_name": "Dypsis lutescens",
     "category": CAT_PALM, "sunlight": "partial_shade", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","indoor","tropical","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Palm","Indoor"]},
    {"name": "Fishtail Palm", "scientific_name": "Caryota mitis",
     "category": CAT_PALM, "sunlight": "partial_shade", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Palm","Tropical"]},
    {"name": "Pygmy Date Palm", "scientific_name": "Phoenix roebelenii",
     "category": CAT_PALM, "sunlight": "partial_shade", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Palm","Easy Care"]},
    {"name": "Foxtail Palm", "scientific_name": "Wodyetia bifurcata",
     "category": CAT_PALM, "sunlight": "full_sun", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Palm","Tropical"]},
    {"name": "Nibung Palm", "scientific_name": "Oncosperma tigillarium",
     "category": CAT_PALM, "sunlight": "full_sun", "water": "high",
     "habit": "palm", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Palm","Tropical"]},
    {"name": "Sealing Wax Palm", "scientific_name": "Cyrtostachys renda",
     "category": CAT_PALM, "sunlight": "full_sun", "water": "high",
     "habit": "palm", "landscape": ["ornamental","colorful","tropical","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Full Sun","Palm","Colorful"]},
    {"name": "Kentia Palm", "scientific_name": "Howea forsteriana",
     "category": CAT_PALM, "sunlight": "partial_shade", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","indoor","tropical"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Palm","Indoor"]},
    {"name": "Lady Palm", "scientific_name": "Rhapis excelsa",
     "category": CAT_PALM, "sunlight": "partial_shade", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","indoor","tropical"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Palm","Indoor"]},
    {"name": "Travellers Palm", "scientific_name": "Ravenala madagascariensis",
     "category": CAT_PALM, "sunlight": "full_sun", "water": "medium",
     "habit": "palm", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Palm","Tropical"]},

    # === INDOOR FOLIAGE ===
    {"name": "Pothos", "scientific_name": "Epipremnum aureum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "low",
     "habit": "vine", "landscape": ["ornamental","indoor","climber"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Snake Plant", "scientific_name": "Dracaena trifasciata",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "low",
     "habit": "herb", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Monstera", "scientific_name": "Monstera deliciosa",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","indoor","tropical"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Tropical"]},
    {"name": "Chinese Evergreen", "scientific_name": "Aglaonema commutatum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","colorful"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Shade","Indoor","Easy Care"]},
    {"name": "ZZ Plant", "scientific_name": "Zamioculcas zamiifolia",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_shade", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Shade","Indoor","Low Water"]},
    {"name": "Rubber Plant", "scientific_name": "Ficus elastica",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","indoor","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Weeping Fig", "scientific_name": "Ficus benjamina",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","indoor","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Indoor","Shade Tree"]},
    {"name": "Calathea", "scientific_name": "Calathea orbifolia",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","colorful"],
     "maintenance": "medium", "flowering": False, "tags": ["Full Shade","Indoor","Colorful Foliage"]},
    {"name": "Prayer Plant", "scientific_name": "Maranta leuconeura",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","colorful"],
     "maintenance": "medium", "flowering": False, "tags": ["Full Shade","Indoor","Colorful Foliage"]},
    {"name": "Philodendron", "scientific_name": "Philodendron hederaceum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","indoor","climber"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Dieffenbachia", "scientific_name": "Dieffenbachia seguine",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","colorful"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Colorful Foliage"]},
    {"name": "Syngonium", "scientific_name": "Syngonium podophyllum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "vine", "landscape": ["ornamental","indoor","climber"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Schefflera", "scientific_name": "Schefflera actinophylla",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","indoor","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Spider Plant", "scientific_name": "Chlorophytum comosum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Dracaena", "scientific_name": "Dracaena fragrans",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "low",
     "habit": "shrub", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Croton", "scientific_name": "Codiaeum variegatum",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","colorful","hedge","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Full Sun","Colorful Foliage","Hedge"]},
    {"name": "African Violet", "scientific_name": "Saintpaulia ionantha",
     "category": CAT_INDOOR_FOLIAGE, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["ornamental","indoor","flowering"],
     "maintenance": "medium", "flowering": True, "tags": ["Partial Shade","Indoor","Flowering"]},

    # === SUCCULENTS ===
    {"name": "Aloe Vera", "scientific_name": "Aloe barbadensis miller",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","indoor","succulent"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Low Water","Easy Care"]},
    {"name": "Crown of Thorns", "scientific_name": "Euphorbia milii",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","flowering","colorful","succulent"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Jade Plant", "scientific_name": "Crassula ovata",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","indoor","succulent"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Low Water","Indoor"]},
    {"name": "Echeveria", "scientific_name": "Echeveria sp.",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","colorful","succulent"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Colorful"]},
    {"name": "Haworthia", "scientific_name": "Haworthia fasciata",
     "category": CAT_SUCCULENT, "sunlight": "partial_shade", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","indoor","succulent"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Low Water","Indoor"]},
    {"name": "String of Pearls", "scientific_name": "Curio rowleyanus",
     "category": CAT_SUCCULENT, "sunlight": "partial_shade", "water": "low",
     "habit": "vine", "landscape": ["ornamental","indoor","succulent"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Low Water","Indoor"]},
    {"name": "Kalanchoe", "scientific_name": "Kalanchoe blossfeldiana",
     "category": CAT_SUCCULENT, "sunlight": "full_sun", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","flowering","colorful","indoor"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Moon Cactus", "scientific_name": "Gymnocalycium mihanovichii",
     "category": CAT_SUCCULENT, "sunlight": "partial_shade", "water": "low",
     "habit": "succulent", "landscape": ["ornamental","colorful","indoor","succulent"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Low Water","Indoor"]},

    # === GROUNDCOVERS ===
    {"name": "Blue Daze", "scientific_name": "Evolvulus glomeratus",
     "category": CAT_GROUNDCOVER, "sunlight": "full_sun", "water": "medium",
     "habit": "groundcover", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Portulaca", "scientific_name": "Portulaca grandiflora",
     "category": CAT_GROUNDCOVER, "sunlight": "full_sun", "water": "low",
     "habit": "groundcover", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Wedelia", "scientific_name": "Sphagneticola trilobata",
     "category": CAT_GROUNDCOVER, "sunlight": "full_sun", "water": "medium",
     "habit": "groundcover", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Easy Care"]},
    {"name": "Torenia", "scientific_name": "Torenia fournieri",
     "category": CAT_GROUNDCOVER, "sunlight": "partial_shade", "water": "medium",
     "habit": "groundcover", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Colorful"]},
    {"name": "Moss Rose", "scientific_name": "Portulaca oleracea",
     "category": CAT_GROUNDCOVER, "sunlight": "full_sun", "water": "low",
     "habit": "groundcover", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Artillery Plant", "scientific_name": "Pilea microphylla",
     "category": CAT_GROUNDCOVER, "sunlight": "partial_shade", "water": "medium",
     "habit": "groundcover", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Dwarf Mondo Grass", "scientific_name": "Ophiopogon japonicus",
     "category": CAT_GROUNDCOVER, "sunlight": "partial_shade", "water": "medium",
     "habit": "grass", "landscape": ["ornamental","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Groundcover","Easy Care"]},
    {"name": "Baby Tears", "scientific_name": "Soleirolia soleirolii",
     "category": CAT_GROUNDCOVER, "sunlight": "partial_shade", "water": "high",
     "habit": "groundcover", "landscape": ["ornamental","indoor","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Groundcover","Indoor"]},

    # === TREES ===
    {"name": "Yellow Flame Tree", "scientific_name": "Peltophorum pterocarpum",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["ornamental","flowering","colorful","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Pink Trumpet Tree", "scientific_name": "Tabebuia rosea",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["ornamental","flowering","colorful","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Rain Tree", "scientific_name": "Samanea saman",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["shade","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Low Water","Shade Tree"]},
    {"name": "Angsana", "scientific_name": "Pterocarpus indicus",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","flowering","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Shade Tree","Easy Care"]},
    {"name": "Tembusu", "scientific_name": "Fagraea fragrans",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","flowering","fragrance","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fragrant","Shade Tree"]},
    {"name": "Sea Apple", "scientific_name": "Syzygium grande",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Shade Tree","Easy Care"]},
    {"name": "Jacaranda", "scientific_name": "Jacaranda mimosifolia",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["ornamental","flowering","colorful","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Shade Tree"]},
    {"name": "Bottlebrush", "scientific_name": "Callistemon viminalis",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "low",
     "habit": "tree", "landscape": ["ornamental","flowering","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Flowering"]},
    {"name": "Palembang Tree", "scientific_name": "Spathodea campanulata",
     "category": CAT_TREE, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["ornamental","flowering","colorful","shade"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Flowering","Tropical"]},

    # === FRUIT ===
    {"name": "Mango", "scientific_name": "Mangifera indica",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","shade","landscaping"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},
    {"name": "Guava", "scientific_name": "Psidium guajava",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},
    {"name": "Lime", "scientific_name": "Citrus aurantifolia",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","fragrance"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Fruit","Fragrant"]},
    {"name": "Papaya", "scientific_name": "Carica papaya",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},
    {"name": "Banana", "scientific_name": "Musa paradisiaca",
     "category": CAT_FRUIT, "sunlight": "partial_shade", "water": "high",
     "habit": "tree", "landscape": ["fruit","tropical","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Fruit","Tropical"]},
    {"name": "Starfruit", "scientific_name": "Averrhoa carambola",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},
    {"name": "Rambutan", "scientific_name": "Nephelium lappaceum",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","shade","landscaping"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Fruit","Shade Tree"]},
    {"name": "Jambu Air", "scientific_name": "Syzygium aqueum",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","shade"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},
    {"name": "Mulberry", "scientific_name": "Morus rubra",
     "category": CAT_FRUIT, "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Easy Care"]},

    # === HERBS ===
    {"name": "Pandan", "scientific_name": "Pandanus amaryllifolius",
     "category": CAT_HERB, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["fragrance","indoor","culinary"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Fragrant","Easy Care"]},
    {"name": "Lemongrass", "scientific_name": "Cymbopogon citratus",
     "category": CAT_HERB, "sunlight": "full_sun", "water": "medium",
     "habit": "grass", "landscape": ["fragrance","culinary"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Fragrant","Easy Care"]},
    {"name": "Rosemary", "scientific_name": "Salvia rosmarinus",
     "category": CAT_HERB, "sunlight": "full_sun", "water": "low",
     "habit": "shrub", "landscape": ["fragrance","culinary"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Fragrant"]},
    {"name": "Basil", "scientific_name": "Ocimum basilicum",
     "category": CAT_HERB, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["fragrance","culinary","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Fragrant","Easy Care"]},
    {"name": "Turmeric", "scientific_name": "Curcuma longa",
     "category": CAT_HERB, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["culinary","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Culinary","Easy Care"]},
    {"name": "Ginger", "scientific_name": "Zingiber officinale",
     "category": CAT_HERB, "sunlight": "partial_shade", "water": "medium",
     "habit": "herb", "landscape": ["culinary","tropical"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Culinary","Tropical"]},
    {"name": "Curry Leaf", "scientific_name": "Murraya koenigii",
     "category": CAT_HERB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["culinary","fragrance"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Culinary","Fragrant"]},
    {"name": "Kaffir Lime", "scientific_name": "Citrus hystrix",
     "category": CAT_HERB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["culinary","fragrance","fruit"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Culinary","Fragrant"]},
    {"name": "Mint", "scientific_name": "Mentha spicata",
     "category": CAT_HERB, "sunlight": "partial_shade", "water": "high",
     "habit": "herb", "landscape": ["culinary","fragrance","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Culinary","Fragrant"]},
    {"name": "Chilli", "scientific_name": "Capsicum annuum",
     "category": CAT_HERB, "sunlight": "full_sun", "water": "medium",
     "habit": "shrub", "landscape": ["culinary","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Culinary","Easy Care"]},

    # === AQUATIC ===
    {"name": "Water Lily", "scientific_name": "Nymphaea sp.",
     "category": CAT_AQUATIC, "sunlight": "full_sun", "water": "high",
     "habit": "aquatic", "landscape": ["ornamental","flowering","colorful","aquatic"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Water Plant","Flowering"]},
    {"name": "Lotus", "scientific_name": "Nelumbo nucifera",
     "category": CAT_AQUATIC, "sunlight": "full_sun", "water": "high",
     "habit": "aquatic", "landscape": ["ornamental","flowering","fragrance","aquatic","colorful"],
     "maintenance": "medium", "flowering": True, "tags": ["Full Sun","Water Plant","Fragrant"]},
    {"name": "Water Hyacinth", "scientific_name": "Eichhornia crassipes",
     "category": CAT_AQUATIC, "sunlight": "full_sun", "water": "high",
     "habit": "aquatic", "landscape": ["ornamental","flowering","aquatic"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Water Plant","Flowering"]},
    {"name": "Taro", "scientific_name": "Colocasia esculenta",
     "category": CAT_AQUATIC, "sunlight": "partial_shade", "water": "high",
     "habit": "aquatic", "landscape": ["ornamental","colorful","tropical","aquatic"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Tropical","Colorful Foliage"]},
    {"name": "Papyrus", "scientific_name": "Cyperus papyrus",
     "category": CAT_AQUATIC, "sunlight": "full_sun", "water": "high",
     "habit": "grass", "landscape": ["ornamental","aquatic","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Water Plant","Easy Care"]},

    # === FERNS ===
    {"name": "Boston Fern", "scientific_name": "Nephrolepis exaltata",
     "category": CAT_FERN, "sunlight": "partial_shade", "water": "high",
     "habit": "fern", "landscape": ["ornamental","indoor","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Birds Nest Fern", "scientific_name": "Asplenium nidus",
     "category": CAT_FERN, "sunlight": "partial_shade", "water": "medium",
     "habit": "fern", "landscape": ["ornamental","indoor","tropical"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Tropical"]},
    {"name": "Staghorn Fern", "scientific_name": "Platycerium bifurcatum",
     "category": CAT_FERN, "sunlight": "partial_shade", "water": "medium",
     "habit": "fern", "landscape": ["ornamental","indoor","tropical"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Indoor","Tropical"]},
    {"name": "Tree Fern", "scientific_name": "Cyathea cooperi",
     "category": CAT_FERN, "sunlight": "partial_shade", "water": "high",
     "habit": "fern", "landscape": ["ornamental","tropical","landscaping"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Tropical","Shade"]},

    # === GRASS & BAMBOO ===
    {"name": "Bamboo", "scientific_name": "Bambusa vulgaris",
     "category": CAT_GRASS, "sunlight": "full_sun", "water": "medium",
     "habit": "grass", "landscape": ["ornamental","landscaping","hedge","shade"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Bamboo","Easy Care"]},
    {"name": "Ornamental Grass", "scientific_name": "Pennisetum setaceum",
     "category": CAT_GRASS, "sunlight": "full_sun", "water": "low",
     "habit": "grass", "landscape": ["ornamental","colorful","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Ornamental"]},
    {"name": "Sweet Flag", "scientific_name": "Acorus gramineus",
     "category": CAT_GRASS, "sunlight": "partial_shade", "water": "high",
     "habit": "grass", "landscape": ["ornamental","indoor","aquatic"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Fountain Grass", "scientific_name": "Pennisetum alopecuroides",
     "category": CAT_GRASS, "sunlight": "full_sun", "water": "low",
     "habit": "grass", "landscape": ["ornamental","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Low Water","Ornamental"]},
    # === ADDITIONAL PLANTS (to 150) ===
    {"name": "Hoya", "scientific_name": "Hoya carnosa",
     "category": "Indoor Foliage", "sunlight": "partial_shade", "water": "low",
     "habit": "vine", "landscape": ["ornamental","indoor","flowering","fragrance"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Indoor","Fragrant"]},
    {"name": "Peperomia", "scientific_name": "Peperomia obtusifolia",
     "category": "Indoor Foliage", "sunlight": "partial_shade", "water": "low",
     "habit": "herb", "landscape": ["ornamental","indoor"],
     "maintenance": "easy", "flowering": False, "tags": ["Partial Shade","Indoor","Easy Care"]},
    {"name": "Alocasia", "scientific_name": "Alocasia macrorrhizos",
     "category": "Indoor Foliage", "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","indoor","tropical","colorful"],
     "maintenance": "medium", "flowering": False, "tags": ["Partial Shade","Indoor","Tropical"]},
    {"name": "Jackfruit", "scientific_name": "Artocarpus heterophyllus",
     "category": "Fruit", "sunlight": "full_sun", "water": "medium",
     "habit": "tree", "landscape": ["fruit","shade","landscaping"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Fruit","Shade Tree"]},
    {"name": "Ulam Raja", "scientific_name": "Cosmos caudatus",
     "category": "Herb", "sunlight": "full_sun", "water": "medium",
     "habit": "herb", "landscape": ["culinary","ornamental","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Full Sun","Culinary","Flowering"]},
    {"name": "Vetiver Grass", "scientific_name": "Chrysopogon zizanioides",
     "category": "Grass", "sunlight": "full_sun", "water": "low",
     "habit": "grass", "landscape": ["ornamental","fragrance","landscaping"],
     "maintenance": "easy", "flowering": False, "tags": ["Full Sun","Low Water","Fragrant"]},
    {"name": "Jacobinia", "scientific_name": "Justicia carnea",
     "category": "Flowering Shrub", "sunlight": "partial_shade", "water": "medium",
     "habit": "shrub", "landscape": ["ornamental","flowering","colorful"],
     "maintenance": "easy", "flowering": True, "tags": ["Partial Shade","Flowering","Easy Care"]},
]

# --- Scoring constants ---
_SUNLIGHT_RANK = {"full_sun": 0, "partial_shade": 1, "full_shade": 2}
_WATER_RANK    = {"low": 0, "medium": 1, "high": 2}

_RELATED_HABITS: dict[str, set[str]] = {
    "vine":        {"shrub"},
    "shrub":       {"vine", "tree", "groundcover"},
    "tree":        {"shrub", "palm"},
    "herb":        {"groundcover", "grass"},
    "groundcover": {"shrub", "herb"},
    "grass":       {"herb", "groundcover"},
    "succulent":   {"shrub"},
    "palm":        {"tree"},
    "fern":        {"herb", "groundcover"},
    "aquatic":     set(),
}

_SUNLIGHT_DESC = {
    "full_sun":      "full-sun",
    "partial_shade": "semi-shade",
    "full_shade":    "shade-tolerant",
}
_HABIT_NAMES = {
    "vine":        "vine",
    "shrub":       "shrub",
    "tree":        "tree",
    "herb":        "herb",
    "groundcover": "ground cover",
    "succulent":   "succulent",
    "aquatic":     "water plant",
    "grass":       "grass",
    "palm":        "palm",
    "fern":        "fern",
}

_RELATED_CATEGORIES: dict[str, set[str]] = {
    CAT_FLOWERING_SHRUB:    {CAT_TROPICAL_FLOWERING, CAT_FLOWERING_VINE},
    CAT_FLOWERING_VINE:     {CAT_FLOWERING_SHRUB},
    CAT_TROPICAL_FLOWERING: {CAT_FLOWERING_SHRUB, CAT_ORCHID},
    CAT_ORCHID:             {CAT_TROPICAL_FLOWERING, CAT_INDOOR_FOLIAGE},
    CAT_INDOOR_FOLIAGE:     {CAT_ORCHID, CAT_FERN, CAT_SUCCULENT},
    CAT_SUCCULENT:          {CAT_INDOOR_FOLIAGE},
    CAT_PALM:               {CAT_TREE},
    CAT_TREE:               {CAT_PALM, CAT_FRUIT},
    CAT_FRUIT:              {CAT_TREE},
    CAT_GROUNDCOVER:        {CAT_FLOWERING_SHRUB, CAT_GRASS},
    CAT_GRASS:              {CAT_GROUNDCOVER, CAT_HERB},
    CAT_HERB:               {CAT_GRASS},
    CAT_FERN:               {CAT_INDOOR_FOLIAGE},
    CAT_AQUATIC:            set(),
}


# --- Attribute extraction from AI result ---

def _extract_attrs(result: dict) -> dict:
    """Map the raw AI identify result to normalised attribute keys."""
    ident       = result.get("identification", {})
    suitability = result.get("suitability", {})
    growing     = result.get("growing", {})
    maintenance = result.get("maintenance", {})
    flowering   = result.get("flowering", {})
    cat         = result.get("cultivation_category", "")

    sun_raw = suitability.get("sunlight", "").lower()
    if "partial" in sun_raw or "semi" in sun_raw:
        sunlight = "partial_shade"
    elif "full shade" in sun_raw or (sun_raw.startswith("shade") and "partial" not in sun_raw):
        sunlight = "full_shade"
    else:
        sunlight = "full_sun"

    water_raw = growing.get("watering", "").lower()
    if "daily" in water_raw or "twice" in water_raw:
        water = "high"
    elif "fortnightly" in water_raw or "monthly" in water_raw or "infrequent" in water_raw:
        water = "low"
    else:
        water = "medium"

    plant_type = ident.get("plant_type", "").lower()
    desc_lower = ident.get("description", "").lower()
    if "vine" in plant_type or "climber" in plant_type or "creeper" in plant_type:
        habit = "vine"
    elif "palm" in plant_type or "palm" in desc_lower:
        habit = "palm"
    elif "tree" in plant_type:
        habit = "tree"
    elif "succulent" in plant_type or "cactus" in plant_type:
        habit = "succulent"
    elif "aquatic" in plant_type or "water" in plant_type:
        habit = "aquatic"
    elif "fern" in plant_type or "fern" in desc_lower:
        habit = "fern"
    elif "grass" in plant_type or "bamboo" in plant_type:
        habit = "grass"
    elif "herb" in plant_type or "annual" in plant_type:
        habit = "herb"
    elif "groundcover" in plant_type or "ground cover" in plant_type:
        habit = "groundcover"
    else:
        habit = "shrub"

    diff = maintenance.get("difficulty", "").lower()
    maint = "easy" if diff == "easy" else ("hard" if diff == "hard" else "medium")

    flower_color = flowering.get("flower_color", "N/A").lower()
    has_flower = flower_color not in ("n/a", "none", "")

    category = _infer_category(result, habit, has_flower, cat)

    best_loc = suitability.get("best_location", {})
    landscape: set[str] = set()
    if has_flower:
        landscape.add("flowering")
    combined = f"{desc_lower} {plant_type} {ident.get('plant_name','').lower()}"
    if any(w in combined for w in ("fragrant", "fragrance", "scent", "aromatic", "jasmine")):
        landscape.add("fragrance")
    if "fruit" in plant_type or "vegetable" in plant_type:
        landscape.add("fruit")
    if habit in ("vine",) or "climber" in plant_type:
        landscape.add("climber")
    if "ornamental" in plant_type or has_flower:
        landscape.add("ornamental")
    if best_loc.get("indoor") or "indoor" in plant_type:
        landscape.add("indoor")
    if best_loc.get("front_yard") or "landscape" in combined:
        landscape.add("landscaping")
    if any(w in combined for w in ("hedge", "screen", "border")):
        landscape.add("hedge")
    if any(w in combined for w in ("tropical", "exotic", "rainforest")):
        landscape.add("tropical")
    if any(w in combined for w in ("succulent", "cactus", "drought")):
        landscape.add("succulent")
    if "aquatic" in combined or "pond" in combined or "water plant" in combined:
        landscape.add("aquatic")
    if any(w in combined for w in ("culinary", "cooking", "herb", "spice", "edible")):
        landscape.add("culinary")
    if "orchid" in combined:
        landscape.add("orchid")
    if not landscape:
        landscape.add("ornamental")

    return {
        "sunlight":    sunlight,
        "water":       water,
        "habit":       habit,
        "landscape":   landscape,
        "maintenance": maint,
        "flowering":   has_flower,
        "category":    category,
    }


def _infer_category(result: dict, habit: str, flowering: bool, cult_cat: str) -> str:
    """Map plant attributes to one of the CAT_* constants."""
    ident      = result.get("identification", {})
    plant_type = ident.get("plant_type", "").lower()
    plant_name = ident.get("plant_name", "").lower()
    desc       = ident.get("description", "").lower()
    combined   = f"{plant_type} {plant_name} {desc} {cult_cat.lower()}"

    if "orchid" in combined:
        return CAT_ORCHID
    if habit == "palm" or "palm" in combined:
        return CAT_PALM
    if "succulent" in combined or "cactus" in combined:
        return CAT_SUCCULENT
    if habit == "aquatic" or "aquatic" in combined or "water lily" in combined:
        return CAT_AQUATIC
    if habit == "fern" or "fern" in combined:
        return CAT_FERN
    if habit == "grass" or "bamboo" in combined or "grass" in plant_type:
        return CAT_GRASS
    if "fruit" in plant_type or "vegetable" in plant_type:
        return CAT_FRUIT
    if any(w in combined for w in ("culinary", "herb", "basil", "mint", "ginger",
                                    "turmeric", "pandan", "lemongrass", "edible")):
        return CAT_HERB
    if habit == "groundcover":
        return CAT_GROUNDCOVER
    if habit == "tree":
        return CAT_TREE
    if habit == "vine":
        return CAT_FLOWERING_VINE
    if any(w in combined for w in ("tropical", "ginger", "heliconia", "anthurium",
                                    "torch", "strelitzia")):
        return CAT_TROPICAL_FLOWERING
    if any(w in combined for w in ("indoor", "foliage")) and not flowering:
        return CAT_INDOOR_FOLIAGE
    if flowering:
        return CAT_FLOWERING_SHRUB
    return CAT_FLOWERING_SHRUB


# --- Similarity scoring ---

def _score(input_attrs: dict, plant: dict) -> float:
    score = 0.0

    # Category match (30%) — exact = full, related = half
    a_cat = input_attrs.get("category", "")
    b_cat = plant.get("category", "")
    if a_cat and b_cat:
        if a_cat == b_cat:
            score += 0.30
        elif b_cat in _RELATED_CATEGORIES.get(a_cat, set()):
            score += 0.15

    # Landscape use overlap (20%)
    a_land = input_attrs["landscape"]
    b_land = set(plant["landscape"])
    union = a_land | b_land
    if union:
        score += (len(a_land & b_land) / len(union)) * 0.20

    # Growth habit (20%)
    a_habit = input_attrs["habit"]
    b_habit = plant["habit"]
    if a_habit == b_habit:
        score += 0.20
    elif b_habit in _RELATED_HABITS.get(a_habit, set()):
        score += 0.10

    # Sunlight (10%)
    a_sun = input_attrs["sunlight"]
    b_sun = plant["sunlight"]
    if a_sun == b_sun:
        score += 0.10
    elif abs(_SUNLIGHT_RANK[a_sun] - _SUNLIGHT_RANK[b_sun]) == 1:
        score += 0.05

    # Water (10%)
    a_wat = input_attrs["water"]
    b_wat = plant["water"]
    if a_wat == b_wat:
        score += 0.10
    elif abs(_WATER_RANK[a_wat] - _WATER_RANK[b_wat]) == 1:
        score += 0.05

    # Maintenance (5%)
    if input_attrs["maintenance"] == plant["maintenance"]:
        score += 0.05

    # Flowering (5%)
    if input_attrs["flowering"] == plant["flowering"]:
        score += 0.05

    return score


# --- Reason string generation ---

def _make_reason(input_attrs: dict, plant: dict) -> str:
    p_land = set(plant["landscape"])
    p_cat  = plant.get("category", "")

    if p_cat == CAT_ORCHID:
        emoji = "orchid"
    elif p_cat == CAT_PALM:
        emoji = "palm"
    elif p_cat == CAT_SUCCULENT:
        emoji = "succulent"
    elif p_cat == CAT_AQUATIC:
        emoji = "water"
    elif p_cat == CAT_FRUIT:
        emoji = "fruit"
    elif p_cat == CAT_HERB:
        emoji = "herb"
    elif "fragrance" in input_attrs["landscape"] and "fragrance" in p_land:
        emoji = "fragrant"
    elif plant["flowering"] and input_attrs["flowering"]:
        emoji = "flowering"
    elif plant["sunlight"] == input_attrs["sunlight"] == "full_sun":
        emoji = "sun"
    elif plant["water"] == input_attrs["water"] == "low":
        emoji = "drought"
    elif plant["sunlight"] == input_attrs["sunlight"] == "partial_shade":
        emoji = "shade"
    else:
        emoji = "similar"

    emoji_map = {
        "orchid": "🌸", "palm": "🌴", "succulent": "🌵", "water": "🌊",
        "fruit": "🍊", "herb": "🌿", "fragrant": "🌸", "flowering": "🌺",
        "sun": "🌞", "drought": "💧", "shade": "⛅", "similar": "🌿",
    }
    icon = emoji_map.get(emoji, "🌿")

    parts = []
    if input_attrs["water"] == "low" and plant["water"] == "low":
        parts.append("drought-tolerant")
    parts.append(_SUNLIGHT_DESC[plant["sunlight"]])
    if "fragrance" in input_attrs["landscape"] and "fragrance" in p_land:
        parts.append("fragrant")
    elif plant["flowering"]:
        parts.append("flowering")
    parts.append(_HABIT_NAMES.get(plant["habit"], plant["habit"]))

    desc = " ".join(parts)
    return f"{icon} Similar {desc[0].lower()}{desc[1:]}"


# --- Public API ---

def get_similar_plants(result: dict, max_results: int = 5) -> list[dict]:
    """
    Given a full identify-result dict, return the top similar Malaysian plants.

    Returns up to max_results entries, each:
        {name, scientific_name, reason, tags, score, category}
    """
    input_attrs = _extract_attrs(result)
    input_name  = result.get("identification", {}).get("plant_name", "").lower().strip()
    input_sci   = result.get("identification", {}).get("scientific_name", "").lower().strip()

    scored: list[tuple[float, dict]] = []
    for plant in _PLANTS:
        if plant["name"].lower() == input_name or plant["scientific_name"].lower() == input_sci:
            continue
        scored.append((_score(input_attrs, plant), plant))

    scored.sort(key=lambda x: -x[0])

    return [
        {
            "name":            p["name"],
            "scientific_name": p["scientific_name"],
            "reason":          _make_reason(input_attrs, p),
            "tags":            p["tags"],
            "score":           round(raw_score * 100),
            "category":        p.get("category", ""),
        }
        for raw_score, p in scored[:max_results]
    ]

# =============================================================================
# VISUAL SIMILARITY SYSTEM (v2)
# Maps plant name → botanical visual attributes for flower-based matching.
# =============================================================================

# flower_shape values:
#   trumpet | tubular | star | daisy | lily | rose | clustered | spike | spathe | orchid | none
# bloom_style values:
#   vine_flower | shrub_flower | tree_flower | ground_flower | tropical_spike | orchid | aquatic_flower | none
_VISUAL: dict[str, dict] = {
    # === FLOWERING VINES ===
    "Bougainvillea":        {"fam":"Nyctaginaceae",    "shape":"clustered", "colors":["pink","purple","red","orange","white","magenta"],  "bloom":"vine_flower"},
    "Allamanda":            {"fam":"Apocynaceae",       "shape":"trumpet",   "colors":["yellow"],                                          "bloom":"vine_flower"},
    "Mandevilla":           {"fam":"Apocynaceae",       "shape":"trumpet",   "colors":["pink","red","white"],                              "bloom":"vine_flower"},
    "Rangoon Creeper":      {"fam":"Combretaceae",      "shape":"tubular",   "colors":["red","pink","white"],                              "bloom":"vine_flower"},
    "Coral Vine":           {"fam":"Polygonaceae",      "shape":"clustered", "colors":["pink","white"],                                    "bloom":"vine_flower"},
    "Flame Vine":           {"fam":"Bignoniaceae",      "shape":"tubular",   "colors":["orange","yellow"],                                 "bloom":"vine_flower"},
    "Blue Trumpet Vine":    {"fam":"Acanthaceae",       "shape":"trumpet",   "colors":["blue","purple"],                                   "bloom":"vine_flower"},
    "Star Jasmine":         {"fam":"Oleaceae",          "shape":"star",      "colors":["white"],                                           "bloom":"vine_flower"},
    "Black-eyed Susan Vine":{"fam":"Acanthaceae",       "shape":"daisy",     "colors":["orange","yellow","white"],                         "bloom":"vine_flower"},
    "Petrea":               {"fam":"Verbenaceae",       "shape":"clustered", "colors":["purple","blue"],                                   "bloom":"vine_flower"},
    "Clerodendrum":         {"fam":"Lamiaceae",         "shape":"star",      "colors":["white","red"],                                     "bloom":"vine_flower"},
    "Wisteria":             {"fam":"Fabaceae",          "shape":"clustered", "colors":["purple","white","pink"],                           "bloom":"vine_flower"},
    # === FLOWERING SHRUBS - FULL SUN ===
    "Hibiscus":             {"fam":"Malvaceae",         "shape":"rose",      "colors":["red","pink","yellow","white","orange"],            "bloom":"shrub_flower"},
    "Ixora":                {"fam":"Rubiaceae",         "shape":"clustered", "colors":["red","orange","pink","yellow"],                    "bloom":"shrub_flower"},
    "Yellow Bells":         {"fam":"Bignoniaceae",      "shape":"trumpet",   "colors":["yellow"],                                          "bloom":"shrub_flower"},
    "Plumbago":             {"fam":"Plumbaginaceae",    "shape":"clustered", "colors":["blue","white"],                                    "bloom":"shrub_flower"},
    "Golden Dewdrop":       {"fam":"Verbenaceae",       "shape":"clustered", "colors":["blue","purple","white"],                           "bloom":"shrub_flower"},
    "Lantana":              {"fam":"Verbenaceae",       "shape":"clustered", "colors":["orange","yellow","pink","red","multi"],            "bloom":"shrub_flower"},
    "Pentas":               {"fam":"Rubiaceae",         "shape":"star",      "colors":["pink","red","white","purple"],                     "bloom":"shrub_flower"},
    "Barleria":             {"fam":"Acanthaceae",       "shape":"tubular",   "colors":["purple","pink","white"],                           "bloom":"shrub_flower"},
    "Crossandra":           {"fam":"Acanthaceae",       "shape":"tubular",   "colors":["orange","yellow"],                                 "bloom":"shrub_flower"},
    "Ruellia":              {"fam":"Acanthaceae",       "shape":"trumpet",   "colors":["purple","pink","white"],                           "bloom":"shrub_flower"},
    "Salvia":               {"fam":"Lamiaceae",         "shape":"tubular",   "colors":["red","purple","blue","white","pink"],              "bloom":"shrub_flower"},
    "Acalypha":             {"fam":"Euphorbiaceae",     "shape":"spike",     "colors":["red","pink"],                                      "bloom":"shrub_flower"},
    "Turks Cap":            {"fam":"Malvaceae",         "shape":"tubular",   "colors":["red"],                                             "bloom":"shrub_flower"},
    "Firecracker Plant":    {"fam":"Plantaginaceae",    "shape":"tubular",   "colors":["red","orange"],                                    "bloom":"shrub_flower"},
    "Mexican Heather":      {"fam":"Lythraceae",        "shape":"star",      "colors":["purple","pink","white"],                           "bloom":"shrub_flower"},
    "Tibouchina":           {"fam":"Melastomataceae",   "shape":"rose",      "colors":["purple"],                                          "bloom":"shrub_flower"},
    "Kopsia":               {"fam":"Apocynaceae",       "shape":"star",      "colors":["pink","white"],                                    "bloom":"shrub_flower"},
    "Brunfelsia":           {"fam":"Solanaceae",        "shape":"star",      "colors":["purple","white"],                                  "bloom":"shrub_flower"},
    "Hamelia":              {"fam":"Rubiaceae",         "shape":"tubular",   "colors":["orange","red"],                                    "bloom":"shrub_flower"},
    "Quisqualis":           {"fam":"Combretaceae",      "shape":"tubular",   "colors":["red","pink","white"],                              "bloom":"shrub_flower"},
    "Tabernaemontana":      {"fam":"Apocynaceae",       "shape":"star",      "colors":["white"],                                           "bloom":"shrub_flower"},
    # === FLOWERING SHRUBS - PARTIAL SHADE ===
    "Gardenia":             {"fam":"Rubiaceae",         "shape":"rose",      "colors":["white"],                                           "bloom":"shrub_flower"},
    "Jasmine":              {"fam":"Oleaceae",          "shape":"star",      "colors":["white"],                                           "bloom":"shrub_flower"},
    "Mussaenda":            {"fam":"Rubiaceae",         "shape":"star",      "colors":["white","pink","red","yellow"],                     "bloom":"shrub_flower"},
    "Ixora Dwarf":          {"fam":"Rubiaceae",         "shape":"clustered", "colors":["red","orange","yellow"],                           "bloom":"shrub_flower"},
    "Impatiens":            {"fam":"Balsaminaceae",     "shape":"rose",      "colors":["pink","red","orange","white","purple"],            "bloom":"shrub_flower"},
    "Begonia":              {"fam":"Begoniaceae",       "shape":"rose",      "colors":["pink","red","orange","white","yellow"],            "bloom":"shrub_flower"},
    "Peace Lily":           {"fam":"Araceae",           "shape":"spathe",    "colors":["white"],                                           "bloom":"shrub_flower"},
    # === TROPICAL FLOWERING ===
    "Heliconia":            {"fam":"Heliconiaceae",     "shape":"spike",     "colors":["red","orange","yellow"],                           "bloom":"tropical_spike"},
    "Anthurium":            {"fam":"Araceae",           "shape":"spathe",    "colors":["red","pink","white","purple","orange"],            "bloom":"tropical_spike"},
    "Ginger Lily":          {"fam":"Zingiberaceae",     "shape":"spike",     "colors":["white","yellow"],                                  "bloom":"tropical_spike"},
    "Torch Ginger":         {"fam":"Zingiberaceae",     "shape":"spike",     "colors":["red","pink"],                                      "bloom":"tropical_spike"},
    "Alpinia":              {"fam":"Zingiberaceae",     "shape":"spike",     "colors":["red","pink","white"],                              "bloom":"tropical_spike"},
    "Costus":               {"fam":"Costaceae",         "shape":"spike",     "colors":["red","orange","white","yellow"],                   "bloom":"tropical_spike"},
    "Medinilla":            {"fam":"Melastomataceae",   "shape":"clustered", "colors":["pink"],                                            "bloom":"shrub_flower"},
    "Bird of Paradise":     {"fam":"Strelitziaceae",    "shape":"spike",     "colors":["orange","blue"],                                   "bloom":"tropical_spike"},
    "Plumeria":             {"fam":"Apocynaceae",       "shape":"star",      "colors":["white","yellow","pink","red"],                     "bloom":"tree_flower"},
    "Canna Lily":           {"fam":"Cannaceae",         "shape":"lily",      "colors":["red","orange","yellow","pink"],                    "bloom":"tropical_spike"},
    "Red Ginger":           {"fam":"Zingiberaceae",     "shape":"spike",     "colors":["red"],                                             "bloom":"tropical_spike"},
    "Desert Rose":          {"fam":"Apocynaceae",       "shape":"trumpet",   "colors":["red","pink","white","yellow"],                     "bloom":"shrub_flower"},
    # === ORCHIDS ===
    "Dendrobium Orchid":    {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["purple","white","pink","yellow"],                  "bloom":"orchid"},
    "Phalaenopsis Orchid":  {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["white","pink","purple"],                           "bloom":"orchid"},
    "Vanda Orchid":         {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["blue","purple","pink","white"],                    "bloom":"orchid"},
    "Oncidium Orchid":      {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["yellow","brown"],                                  "bloom":"orchid"},
    "Cattleya Orchid":      {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["purple","pink","white","yellow"],                  "bloom":"orchid"},
    "Aranda Orchid":        {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["purple","blue","pink"],                            "bloom":"orchid"},
    "Spathoglottis Orchid": {"fam":"Orchidaceae",       "shape":"orchid",    "colors":["purple","yellow","white","pink"],                  "bloom":"orchid"},
    # === SUCCULENTS ===
    "Aloe Vera":            {"fam":"Asphodelaceae",     "shape":"tubular",   "colors":["orange","red","yellow"],                           "bloom":"shrub_flower"},
    "Crown of Thorns":      {"fam":"Euphorbiaceae",     "shape":"clustered", "colors":["red","pink","yellow","orange"],                    "bloom":"shrub_flower"},
    "Jade Plant":           {"fam":"Crassulaceae",      "shape":"star",      "colors":["white","pink"],                                    "bloom":"shrub_flower"},
    "Echeveria":            {"fam":"Crassulaceae",      "shape":"tubular",   "colors":["pink","orange","red","yellow"],                    "bloom":"shrub_flower"},
    "Haworthia":            {"fam":"Asphodelaceae",     "shape":"tubular",   "colors":["white"],                                           "bloom":"shrub_flower"},
    "Kalanchoe":            {"fam":"Crassulaceae",      "shape":"clustered", "colors":["red","orange","yellow","pink","white"],            "bloom":"shrub_flower"},
    "Moon Cactus":          {"fam":"Cactaceae",         "shape":"daisy",     "colors":["red","orange","yellow","pink"],                    "bloom":"shrub_flower"},
    # === GROUNDCOVERS ===
    "Blue Daze":            {"fam":"Convolvulaceae",    "shape":"trumpet",   "colors":["blue"],                                            "bloom":"ground_flower"},
    "Portulaca":            {"fam":"Portulacaceae",     "shape":"rose",      "colors":["red","pink","orange","yellow","white"],            "bloom":"ground_flower"},
    "Wedelia":              {"fam":"Asteraceae",        "shape":"daisy",     "colors":["yellow"],                                          "bloom":"ground_flower"},
    "Torenia":              {"fam":"Linderniaceae",     "shape":"tubular",   "colors":["purple","pink","white"],                           "bloom":"ground_flower"},
    "Moss Rose":            {"fam":"Portulacaceae",     "shape":"rose",      "colors":["red","pink","orange","yellow","white"],            "bloom":"ground_flower"},
    # === TREES ===
    "Yellow Flame Tree":    {"fam":"Fabaceae",          "shape":"clustered", "colors":["yellow"],                                          "bloom":"tree_flower"},
    "Pink Trumpet Tree":    {"fam":"Bignoniaceae",      "shape":"trumpet",   "colors":["pink","white"],                                    "bloom":"tree_flower"},
    "Angsana":              {"fam":"Fabaceae",          "shape":"clustered", "colors":["yellow"],                                          "bloom":"tree_flower"},
    "Tembusu":              {"fam":"Gentianaceae",      "shape":"star",      "colors":["yellow","white"],                                  "bloom":"tree_flower"},
    "Sea Apple":            {"fam":"Myrtaceae",         "shape":"clustered", "colors":["white","pink"],                                    "bloom":"tree_flower"},
    "Jacaranda":            {"fam":"Bignoniaceae",      "shape":"clustered", "colors":["purple","blue"],                                   "bloom":"tree_flower"},
    "Bottlebrush":          {"fam":"Myrtaceae",         "shape":"spike",     "colors":["red"],                                             "bloom":"tree_flower"},
    "Palembang Tree":       {"fam":"Bignoniaceae",      "shape":"trumpet",   "colors":["red","orange"],                                    "bloom":"tree_flower"},
    # === AQUATIC ===
    "Water Lily":           {"fam":"Nymphaeaceae",      "shape":"lily",      "colors":["white","pink","yellow","purple"],                  "bloom":"aquatic_flower"},
    "Lotus":                {"fam":"Nelumbonaceae",     "shape":"lily",      "colors":["white","pink","yellow"],                           "bloom":"aquatic_flower"},
    "Water Hyacinth":       {"fam":"Pontederiaceae",    "shape":"spike",     "colors":["purple","blue"],                                   "bloom":"aquatic_flower"},
    # === HERBS / MISC ===
    "Rosemary":             {"fam":"Lamiaceae",         "shape":"tubular",   "colors":["blue","purple","white"],                           "bloom":"shrub_flower"},
    "Chilli":               {"fam":"Solanaceae",        "shape":"star",      "colors":["white"],                                           "bloom":"shrub_flower"},
    "Curry Leaf":           {"fam":"Rutaceae",          "shape":"clustered", "colors":["white"],                                           "bloom":"shrub_flower"},
    "Ulam Raja":            {"fam":"Asteraceae",        "shape":"daisy",     "colors":["pink","purple"],                                   "bloom":"ground_flower"},
    "Hoya":                 {"fam":"Apocynaceae",       "shape":"clustered", "colors":["white","pink"],                                    "bloom":"shrub_flower"},
    "African Violet":       {"fam":"Gesneriaceae",      "shape":"star",      "colors":["purple","pink","white"],                           "bloom":"shrub_flower"},
    "Jacobinia":            {"fam":"Acanthaceae",       "shape":"spike",     "colors":["pink","red","orange"],                             "bloom":"shrub_flower"},
    "Crown of Thorns":      {"fam":"Euphorbiaceae",     "shape":"clustered", "colors":["red","pink","yellow"],                             "bloom":"shrub_flower"},
}

_RELATED_SHAPES: dict[str, set] = {
    "trumpet":   {"tubular", "lily"},
    "tubular":   {"trumpet"},
    "lily":      {"trumpet", "rose"},
    "rose":      {"lily"},
    "daisy":     {"clustered", "star"},
    "clustered": {"daisy", "star"},
    "star":      {"clustered", "daisy"},
    "orchid":    set(),
    "spike":     set(),
    "spathe":    set(),
    "none":      set(),
}

_BLOOM_RELATED: dict[str, set] = {
    "vine_flower":    {"shrub_flower"},
    "shrub_flower":   {"vine_flower", "ground_flower", "tree_flower"},
    "tree_flower":    {"shrub_flower"},
    "ground_flower":  {"shrub_flower"},
    "tropical_spike": {"shrub_flower"},
    "orchid":         set(),
    "aquatic_flower": set(),
    "none":           set(),
}


def _infer_flower_shape(desc: str, plant_type: str) -> str:
    combined = f"{desc} {plant_type}".lower()
    if "orchid" in combined:
        return "orchid"
    if "trumpet" in combined or "funnel" in combined:
        return "trumpet"
    if "tubular" in combined:
        return "tubular"
    if "cup-shaped" in combined or "bowl-shaped" in combined or "bowl shaped" in combined or "cup shaped" in combined:
        return "cup"
    if "daisy" in combined or "composite" in combined or "ray floret" in combined:
        return "daisy"
    if "star-shaped" in combined or "star shaped" in combined or "5-petal" in combined:
        return "star"
    if "lily" in combined:
        return "lily"
    if "spathe" in combined or "arum" in combined:
        return "spathe"
    if "spike" in combined or "raceme" in combined or "inflorescence" in combined:
        return "spike"
    if "rose" in combined or "rosette" in combined or "many petal" in combined or "double petal" in combined or "multi-petal" in combined:
        return "rose"
    if "cluster" in combined or "umbel" in combined or "corymb" in combined:
        return "clustered"
    return "unknown"


def _infer_bloom_style(plant_type: str, desc: str) -> str:
    combined = f"{plant_type} {desc}".lower()
    if "orchid" in combined:
        return "orchid"
    if "aquatic" in combined or "pond" in combined or "water lily" in combined or "lotus" in combined:
        return "aquatic_flower"
    if "vine" in combined or "climber" in combined or "creeper" in combined:
        return "vine_flower"
    if "tree" in combined:
        return "tree_flower"
    if any(w in combined for w in ("ginger", "heliconia", "alpinia", "costus", "bird of paradise", "strelitzia", "canna")):
        return "tropical_spike"
    if "groundcover" in combined or "ground cover" in combined:
        return "ground_flower"
    return "shrub_flower"


def _extract_visual_attrs(result: dict) -> dict:
    """Extract visual attributes from an AI identify result.
    Fast path: looks up the plant by name in _KNOWN_PLANT_VISUALS.
    Slow path: parses the AI description text.
    """
    ident = result.get("identification", {})
    flw   = result.get("flowering", {})

    plant_name = ident.get("plant_name", "").lower().strip()
    sci_name   = ident.get("scientific_name", "").lower().strip()

    # Always parse AI colors (supplement known colors)
    color_raw = flw.get("flower_color", "").lower()
    for sep in ["/", " and ", " & "]:
        color_raw = color_raw.replace(sep, ",")
    ai_colors: set[str] = {c.strip() for c in color_raw.split(",")
                           if c.strip() and c.strip() not in ("n/a", "none", "varies", "variable", "multi")}
    if not ai_colors:
        ai_colors = {c.lower().strip() for c in (flw.get("flower_colors") or []) if c}

    # ── Fast path: known plant lookup ──────────────────────────────────────
    for key in (plant_name, sci_name):
        if key and key in _KNOWN_PLANT_VISUALS:
            kv = _KNOWN_PLANT_VISUALS[key]
            known_colors = set(kv.get("colors", []))
            return {
                "family": kv.get("fam", ident.get("plant_family", "").strip()),
                "shape":  kv.get("shape", "unknown"),
                "colors": (ai_colors | known_colors) if known_colors else ai_colors,
                "bloom":  kv.get("bloom", "shrub_flower"),
                "habit":  kv.get("habit", _infer_habit_from_result(result)),
            }

    # ── Slow path: parse from AI description ───────────────────────────────
    family = ident.get("plant_family", "").strip()
    desc   = (ident.get("description", "") + " " + plant_name).lower()
    ptype  = ident.get("plant_type", "").lower()
    shape  = _infer_flower_shape(desc, ptype)
    bloom  = _infer_bloom_style(ptype, desc)

    return {
        "family": family,
        "shape":  shape,
        "colors": ai_colors,
        "bloom":  bloom,
        "habit":  _infer_habit_from_result(result),
    }


def _infer_habit_from_result(result: dict) -> str:
    ident = result.get("identification", {})
    pt = ident.get("plant_type", "").lower()
    desc = ident.get("description", "").lower()
    if "vine" in pt or "climber" in pt:
        return "vine"
    if "palm" in pt or "palm" in desc:
        return "palm"
    if "tree" in pt:
        return "tree"
    if "succulent" in pt or "cactus" in pt:
        return "succulent"
    if "aquatic" in pt:
        return "aquatic"
    if "fern" in pt or "fern" in desc:
        return "fern"
    if "grass" in pt or "bamboo" in pt:
        return "grass"
    if "herb" in pt or "annual" in pt:
        return "herb"
    if "groundcover" in pt:
        return "groundcover"
    return "shrub"


def _get_plant_visual(plant: dict) -> dict:
    """Get visual attributes for a plant from _VISUAL lookup or from the plant's own inline attrs."""
    name = plant.get("name", "")
    if name in _VISUAL:
        return _VISUAL[name]
    # _GLOBAL_FLOWERS entries have inline fam/shape/colors/bloom
    if "fam" in plant:
        return plant
    return {}


def _score_visual(input_vis: dict, plant: dict) -> float:
    """Score a plant on visual similarity to input_vis attributes."""
    pv = _get_plant_visual(plant)
    if not pv:
        return 0.0
    score = 0.0

    # Family match (35%)
    a_fam = input_vis.get("family", "").strip().lower()
    b_fam = pv.get("fam", "").strip().lower()
    if a_fam and b_fam and a_fam == b_fam:
        score += 0.35

    # Flower shape (30%) — use extended shape relations
    a_shape = input_vis.get("shape", "unknown")
    b_shape = pv.get("shape", "")
    if a_shape and b_shape and a_shape not in ("unknown", "none") and a_shape == b_shape:
        score += 0.30
    elif a_shape and b_shape and a_shape not in ("unknown", "none") and b_shape not in ("none",):
        if b_shape in _RELATED_SHAPES_V2.get(a_shape, set()):
            score += 0.15

    # Bloom style (15%)
    a_bloom = input_vis.get("bloom", "")
    b_bloom = pv.get("bloom", "")
    if a_bloom and b_bloom:
        if a_bloom == b_bloom:
            score += 0.15
        elif b_bloom in _BLOOM_RELATED.get(a_bloom, set()):
            score += 0.07

    # Color overlap (15%)
    a_colors = input_vis.get("colors", set())
    b_colors = set(pv.get("colors", []))
    if a_colors and b_colors:
        overlap = len(a_colors & b_colors)
        if overlap > 0:
            score += min(0.15, overlap * 0.05)

    # Habit match (5%)
    if input_vis.get("habit") == plant.get("habit"):
        score += 0.05

    return score


def _make_visual_reason(input_vis: dict, plant: dict) -> str:
    """Generate a reason string for visual similarity."""
    pv    = _get_plant_visual(plant)
    shape = pv.get("shape", "")
    bloom = pv.get("bloom", "")
    fam   = pv.get("fam", "")

    # Pick emoji
    shape_emoji = {
        "trumpet": "🌼", "tubular": "🌼", "lily": "🌸", "rose": "🌹",
        "daisy": "🌻", "star": "⭐", "clustered": "🌸", "orchid": "🌺",
        "spike": "🌿", "spathe": "🌿",
    }
    bloom_emoji = {
        "vine_flower": "🌿", "tree_flower": "🌳", "tropical_spike": "🌴",
        "orchid": "🌸", "aquatic_flower": "🌊", "ground_flower": "🌱",
    }
    icon = shape_emoji.get(shape) or bloom_emoji.get(bloom) or "🌿"

    parts = []
    if fam:
        parts.append(fam)
    if shape and shape not in ("none", "unknown"):
        shape_label = {"trumpet":"trumpet-shaped","tubular":"tubular","lily":"lily-shaped",
                       "rose":"rose-shaped","daisy":"daisy-like","star":"star-shaped",
                       "clustered":"clustered blooms","orchid":"orchid blooms",
                       "spike":"spike blooms","spathe":"spathe flower"}.get(shape, shape)
        parts.append(shape_label)
    if not parts:
        parts.append("similar appearance")

    return f"{icon} {' · '.join(parts)}"


def _make_alternative_reason(input_attrs: dict, plant: dict) -> str:
    """Generate a reason string for Malaysian alternative (care-based)."""
    p_land = set(plant["landscape"])
    p_cat  = plant.get("category", "")

    bloom_label = {
        CAT_ORCHID: ("🌸", "orchid"),
        CAT_PALM:   ("🌴", "palm"),
        CAT_SUCCULENT: ("🌵", "succulent"),
        CAT_AQUATIC: ("🌊", "water plant"),
        CAT_FRUIT:  ("🍊", "fruit tree"),
        CAT_HERB:   ("🌿", "herb"),
    }
    if p_cat in bloom_label:
        icon, label = bloom_label[p_cat]
        return f"{icon} Malaysian {label} · {_SUNLIGHT_DESC[plant['sunlight']]}"

    if "fragrance" in input_attrs.get("landscape", set()) and "fragrance" in p_land:
        icon = "🌸"
    elif plant["flowering"] and input_attrs.get("flowering"):
        icon = "🌺"
    elif plant["sunlight"] == "full_sun":
        icon = "🌞"
    else:
        icon = "🌿"

    parts = [_SUNLIGHT_DESC[plant["sunlight"]]]
    if plant["water"] == "low":
        parts.append("low-water")
    if plant["flowering"]:
        parts.append("flowering")
    parts.append(_HABIT_NAMES.get(plant["habit"], plant["habit"]))
    desc = " · ".join(parts)
    return f"{icon} Malaysia-suitable · {desc}"


# =============================================================================
# NEW PUBLIC API
# =============================================================================

def _img_query(name: str) -> str:
    """Normalize a plant display name for Wikipedia image lookup.
    Strips trailing parentheticals: 'Bird of Paradise (Global)' -> 'Bird of Paradise'
    """
    return _re.sub(r'\s*\([^)]*\)\s*$', '', name).strip()


def get_similar_flowers(result: dict, max_results: int = 5) -> list[dict]:
    """
    Return plants that VISUALLY resemble the scanned plant.
    Searches _GLOBAL_FLOWERS (worldwide flowers) + flowering _PLANTS (Malaysian).
    Scoring: botanical family (35%) + flower shape (30%) + bloom style (15%)
             + color overlap (15%) + habit (5%).
    """
    input_vis  = _extract_visual_attrs(result)
    input_name = result.get("identification", {}).get("plant_name", "").lower().strip()
    input_sci  = result.get("identification", {}).get("scientific_name", "").lower().strip()

    # Build candidate pool: global flowers + Malaysian flowering plants (with _VISUAL entries)
    candidates: list[dict] = []
    seen: set[str] = {input_name, input_sci}

    for gf in _GLOBAL_FLOWERS:
        n = gf["name"].lower()
        sn = gf["scientific_name"].lower()
        if n not in seen and sn not in seen:
            candidates.append(gf)
            seen.add(n)

    for plant in _PLANTS:
        n = plant["name"].lower()
        if n in seen:
            continue
        if plant["name"] in _VISUAL:  # only add Malaysian plants with visual data
            candidates.append(plant)
            seen.add(n)

    scored: list[tuple[float, dict]] = []
    for c in candidates:
        s = _score_visual(input_vis, c)
        if s >= 0.10:  # minimum meaningful threshold
            scored.append((s, c))

    scored.sort(key=lambda x: -x[0])

    return [
        {
            "name":            p["name"],
            "scientific_name": p["scientific_name"],
            "image_query":     _img_query(p["name"]),
            "reason":          _make_visual_reason(input_vis, p),
            "tags":            p["tags"],
            "score":           round(raw_score * 100),
            "category":        p.get("category", ""),
        }
        for raw_score, p in scored[:max_results]
    ]


def get_malaysia_alternatives(result: dict, max_results: int = 5) -> list[dict]:
    """
    Return Malaysia-suitable plants with similar gardening profile.
    Scoring: category (30%) + landscape (20%) + habit (20%) + sunlight (10%)
             + water (10%) + maintenance (5%) + flowering (5%).
    All _PLANTS entries are Malaysia-suitable.
    """
    input_attrs = _extract_attrs(result)
    input_name  = result.get("identification", {}).get("plant_name", "").lower().strip()
    input_sci   = result.get("identification", {}).get("scientific_name", "").lower().strip()

    scored: list[tuple[float, dict]] = []
    for plant in _PLANTS:
        if plant["name"].lower() == input_name or plant["scientific_name"].lower() == input_sci:
            continue
        scored.append((_score(input_attrs, plant), plant))

    scored.sort(key=lambda x: -x[0])

    return [
        {
            "name":            p["name"],
            "scientific_name": p["scientific_name"],
            "image_query":     _img_query(p["name"]),
            "reason":          _make_alternative_reason(input_attrs, p),
            "tags":            p["tags"],
            "score":           round(raw_score * 100),
            "category":        p.get("category", ""),
        }
        for raw_score, p in scored[:max_results]
    ]

# =============================================================================
# GLOBAL FLOWER REFERENCE DATABASE
# Used by get_similar_flowers() — covers worldwide known flowers, NOT limited
# to Malaysia-suitable plants. Each entry:
#   name, scientific_name, fam, shape, colors, bloom, habit, tags
# =============================================================================

_GLOBAL_FLOWERS: list[dict] = [

    # ── Cup / Bowl shaped ────────────────────────────────────────────────────
    {"name": "Tulip", "scientific_name": "Tulipa sp.",
     "fam": "Liliaceae", "shape": "cup", "colors": ["red","pink","yellow","orange","purple","white","multi"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Spring Bulb","Classic","Colorful"]},
    {"name": "Crocus", "scientific_name": "Crocus sativus",
     "fam": "Iridaceae", "shape": "cup", "colors": ["purple","white","yellow","lavender"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Spring Bulb","Small","Ground Flower"]},
    {"name": "Poppy", "scientific_name": "Papaver rhoeas",
     "fam": "Papaveraceae", "shape": "cup", "colors": ["red","orange","pink","white","purple"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Wildflower","Colorful","Delicate"]},
    {"name": "Anemone", "scientific_name": "Anemone coronaria",
     "fam": "Ranunculaceae", "shape": "cup", "colors": ["red","pink","purple","white","blue"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Spring Flower","Colorful","Windflower"]},
    {"name": "Magnolia", "scientific_name": "Magnolia grandiflora",
     "fam": "Magnoliaceae", "shape": "cup", "colors": ["white","pink","purple"],
     "bloom": "tree_flower", "habit": "tree", "tags": ["Fragrant","Large Blooms","Ornamental"]},
    {"name": "Camellia", "scientific_name": "Camellia japonica",
     "fam": "Theaceae", "shape": "rose", "colors": ["red","pink","white"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Winter Blooming","Glossy Leaves","Ornamental"]},
    {"name": "Rose", "scientific_name": "Rosa sp.",
     "fam": "Rosaceae", "shape": "rose", "colors": ["red","pink","white","yellow","orange","purple"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Classic","Fragrant","Garden Rose"]},
    {"name": "Peony", "scientific_name": "Paeonia lactiflora",
     "fam": "Paeoniaceae", "shape": "rose", "colors": ["pink","red","white","yellow"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Fragrant","Lush Blooms","Spring Flower"]},
    {"name": "Ranunculus", "scientific_name": "Ranunculus asiaticus",
     "fam": "Ranunculaceae", "shape": "rose", "colors": ["red","pink","orange","yellow","white"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Layered Petals","Cut Flower","Colorful"]},
    {"name": "Dahlia", "scientific_name": "Dahlia sp.",
     "fam": "Asteraceae", "shape": "rose", "colors": ["red","pink","orange","yellow","purple","white"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Showy Blooms","Colorful","Garden Flower"]},

    # ── Trumpet / Funnel shaped ───────────────────────────────────────────────
    {"name": "Daffodil", "scientific_name": "Narcissus pseudonarcissus",
     "fam": "Amaryllidaceae", "shape": "trumpet", "colors": ["yellow","white","orange"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Spring Bulb","Fragrant","Classic"]},
    {"name": "Narcissus", "scientific_name": "Narcissus sp.",
     "fam": "Amaryllidaceae", "shape": "trumpet", "colors": ["white","yellow","orange"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Spring Bulb","Fragrant","Fragrant"]},
    {"name": "Amaryllis", "scientific_name": "Hippeastrum sp.",
     "fam": "Amaryllidaceae", "shape": "trumpet", "colors": ["red","pink","white","orange","striped"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Indoor Bulb","Large Blooms","Colorful"]},
    {"name": "Rain Lily", "scientific_name": "Zephyranthes sp.",
     "fam": "Amaryllidaceae", "shape": "trumpet", "colors": ["white","pink","yellow","rose"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Low Maintenance","Tropical","Bulb Flower"]},
    {"name": "Angel Trumpet", "scientific_name": "Brugmansia sp.",
     "fam": "Solanaceae", "shape": "trumpet", "colors": ["white","yellow","pink","orange"],
     "bloom": "tree_flower", "habit": "shrub", "tags": ["Fragrant","Large Blooms","Pendulous"]},
    {"name": "Morning Glory", "scientific_name": "Ipomoea purpurea",
     "fam": "Convolvulaceae", "shape": "trumpet", "colors": ["blue","purple","pink","white","red"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Fast Growing","Climber","Colorful"]},

    # ── Star / 5-petal flat ───────────────────────────────────────────────────
    {"name": "Jasmine (Common)", "scientific_name": "Jasminum officinale",
     "fam": "Oleaceae", "shape": "star", "colors": ["white","pink"],
     "bloom": "shrub_flower", "habit": "vine", "tags": ["Fragrant","Classic","White Flower"]},
    {"name": "Plumeria (Frangipani)", "scientific_name": "Plumeria sp.",
     "fam": "Apocynaceae", "shape": "star", "colors": ["white","yellow","pink","red"],
     "bloom": "tree_flower", "habit": "tree", "tags": ["Fragrant","Tropical","Exotic"]},
    {"name": "Vinca (Periwinkle)", "scientific_name": "Catharanthus roseus",
     "fam": "Apocynaceae", "shape": "star", "colors": ["pink","white","red","purple"],
     "bloom": "ground_flower", "habit": "shrub", "tags": ["Low Maintenance","Colorful","Tropical"]},
    {"name": "Phlox", "scientific_name": "Phlox paniculata",
     "fam": "Polemoniaceae", "shape": "star", "colors": ["pink","purple","white","red"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Fragrant","Clustered","Garden Classic"]},
    {"name": "Stephanotis", "scientific_name": "Stephanotis floribunda",
     "fam": "Apocynaceae", "shape": "star", "colors": ["white"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Fragrant","Waxy Flowers","Bridal Flower"]},

    # ── Lily / Lily-bowl ──────────────────────────────────────────────────────
    {"name": "Lily", "scientific_name": "Lilium sp.",
     "fam": "Liliaceae", "shape": "lily", "colors": ["white","pink","orange","yellow","red"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Fragrant","Showy","Cut Flower"]},
    {"name": "Easter Lily", "scientific_name": "Lilium longiflorum",
     "fam": "Liliaceae", "shape": "lily", "colors": ["white"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Fragrant","Pure White","Easter Symbol"]},
    {"name": "Stargazer Lily", "scientific_name": "Lilium orientalis",
     "fam": "Liliaceae", "shape": "lily", "colors": ["pink","white","red"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Fragrant","Upward-Facing","Showy"]},
    {"name": "Iris", "scientific_name": "Iris germanica",
     "fam": "Iridaceae", "shape": "orchid", "colors": ["purple","blue","white","yellow","orange"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Spring Bloomer","Elegant","Colorful"]},
    {"name": "Gladiolus", "scientific_name": "Gladiolus sp.",
     "fam": "Iridaceae", "shape": "lily", "colors": ["red","pink","orange","yellow","white","purple"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Tall Spike","Cut Flower","Colorful"]},
    {"name": "Calla Lily", "scientific_name": "Zantedeschia aethiopica",
     "fam": "Araceae", "shape": "spathe", "colors": ["white","yellow","pink","purple"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Elegant","Weddings","Clean Lines"]},
    {"name": "Day Lily", "scientific_name": "Hemerocallis fulva",
     "fam": "Hemerocallidaceae", "shape": "lily", "colors": ["orange","yellow","red","pink","purple"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Hardy","Long Blooming","Colorful"]},
    {"name": "Alstroemeria", "scientific_name": "Alstroemeria sp.",
     "fam": "Alstroemeriaceae", "shape": "lily", "colors": ["red","pink","orange","yellow","white","purple"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Cut Flower","Colorful","Spotted Petals"]},

    # ── Orchid ────────────────────────────────────────────────────────────────
    {"name": "Moth Orchid", "scientific_name": "Phalaenopsis sp.",
     "fam": "Orchidaceae", "shape": "orchid", "colors": ["white","pink","purple","yellow"],
     "bloom": "orchid", "habit": "shrub", "tags": ["Exotic","Long Blooming","Indoor Orchid"]},
    {"name": "Lady Slipper Orchid", "scientific_name": "Paphiopedilum sp.",
     "fam": "Orchidaceae", "shape": "orchid", "colors": ["green","brown","white","pink"],
     "bloom": "orchid", "habit": "shrub", "tags": ["Exotic","Unusual Shape","Indoor Orchid"]},
    {"name": "Cymbidium Orchid", "scientific_name": "Cymbidium sp.",
     "fam": "Orchidaceae", "shape": "orchid", "colors": ["green","yellow","white","pink","red"],
     "bloom": "orchid", "habit": "shrub", "tags": ["Cut Flower","Cool Growing","Elegant"]},
    {"name": "Oncidium Orchid (Dancing Lady)", "scientific_name": "Oncidium sp.",
     "fam": "Orchidaceae", "shape": "orchid", "colors": ["yellow","brown","red","orange"],
     "bloom": "orchid", "habit": "shrub", "tags": ["Dancing Blooms","Colorful","Cascading"]},

    # ── Daisy / Composite ─────────────────────────────────────────────────────
    {"name": "Sunflower", "scientific_name": "Helianthus annuus",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["yellow","orange","red","brown"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Bold","Sun-Tracking","Summer Flower"]},
    {"name": "Gerbera Daisy", "scientific_name": "Gerbera jamesonii",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["red","orange","pink","yellow","white","purple"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Cut Flower","Colorful","Classic Daisy"]},
    {"name": "Chrysanthemum", "scientific_name": "Chrysanthemum sp.",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["white","yellow","pink","red","purple","orange"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Autumn Bloomer","Long Lasting","Versatile"]},
    {"name": "Zinnia", "scientific_name": "Zinnia elegans",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["red","orange","pink","yellow","white","purple"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Heat Tolerant","Long Blooming","Colorful"]},
    {"name": "Aster", "scientific_name": "Aster sp.",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["purple","blue","pink","white"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Autumn Bloomer","Star-Like","Pollinator"]},
    {"name": "Marigold", "scientific_name": "Tagetes sp.",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["yellow","orange","red"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Pest Deterrent","Long Blooming","Easy Care"]},
    {"name": "Chamomile", "scientific_name": "Matricaria chamomilla",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["white","yellow"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Aromatic","Herb","Delicate"]},
    {"name": "Echinacea (Coneflower)", "scientific_name": "Echinacea purpurea",
     "fam": "Asteraceae", "shape": "daisy", "colors": ["purple","pink","white","orange","red"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Medicinal","Drought Tolerant","Pollinator"]},

    # ── Clustered / Umbel ─────────────────────────────────────────────────────
    {"name": "Hyacinth", "scientific_name": "Hyacinthus orientalis",
     "fam": "Asparagaceae", "shape": "spike", "colors": ["blue","purple","pink","white","red","yellow"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Fragrant","Spring Bulb","Colorful"]},
    {"name": "Snowdrop", "scientific_name": "Galanthus nivalis",
     "fam": "Amaryllidaceae", "shape": "tubular", "colors": ["white"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Early Spring","Delicate","Small Flower"]},
    {"name": "Lilac", "scientific_name": "Syringa vulgaris",
     "fam": "Oleaceae", "shape": "clustered", "colors": ["purple","white","pink","lilac"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Fragrant","Spring Bloomer","Classic"]},
    {"name": "Hydrangea", "scientific_name": "Hydrangea macrophylla",
     "fam": "Hydrangeaceae", "shape": "clustered", "colors": ["blue","pink","white","purple"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Large Blooms","Soil pH Sensitive","Showy"]},
    {"name": "Cherry Blossom", "scientific_name": "Prunus serrulata",
     "fam": "Rosaceae", "shape": "clustered", "colors": ["pink","white"],
     "bloom": "tree_flower", "habit": "tree", "tags": ["Spring Symbol","Delicate","Cultural Icon"]},
    {"name": "Lavender", "scientific_name": "Lavandula angustifolia",
     "fam": "Lamiaceae", "shape": "spike", "colors": ["purple","blue","white","pink"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Fragrant","Aromatic","Medicinal"]},
    {"name": "Allium", "scientific_name": "Allium sp.",
     "fam": "Amaryllidaceae", "shape": "clustered", "colors": ["purple","blue","pink","white"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Globe Flower","Spring Bulb","Architectural"]},
    {"name": "Verbena", "scientific_name": "Verbena sp.",
     "fam": "Verbenaceae", "shape": "clustered", "colors": ["purple","pink","red","white"],
     "bloom": "ground_flower", "habit": "herb", "tags": ["Drought Tolerant","Colorful","Long Blooming"]},

    # ── Tubular / Spike ───────────────────────────────────────────────────────
    {"name": "Foxglove", "scientific_name": "Digitalis purpurea",
     "fam": "Plantaginaceae", "shape": "tubular", "colors": ["purple","pink","white","yellow"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Tall Spike","Bi-Annual","Classic Cottage"]},
    {"name": "Snapdragon", "scientific_name": "Antirrhinum majus",
     "fam": "Plantaginaceae", "shape": "tubular", "colors": ["red","pink","orange","yellow","white","purple"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Classic","Long Spike","Colorful"]},
    {"name": "Delphinium", "scientific_name": "Delphinium sp.",
     "fam": "Ranunculaceae", "shape": "spike", "colors": ["blue","purple","white","pink"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Tall Spike","Blue Flowers","Garden Classic"]},
    {"name": "Lupine", "scientific_name": "Lupinus sp.",
     "fam": "Fabaceae", "shape": "spike", "colors": ["blue","purple","pink","white","yellow","orange"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Tall Spike","Colorful","Cottage Garden"]},
    {"name": "Fuchsia", "scientific_name": "Fuchsia sp.",
     "fam": "Onagraceae", "shape": "tubular", "colors": ["pink","red","purple","white"],
     "bloom": "vine_flower", "habit": "shrub", "tags": ["Pendulous","Shade Loving","Hanging Basket"]},
    {"name": "Hollyhock", "scientific_name": "Alcea rosea",
     "fam": "Malvaceae", "shape": "cup", "colors": ["pink","red","white","yellow","purple","black"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Tall Spike","Old-Fashioned","Cottage Garden"]},

    # ── Shrub / Tree Flowers ──────────────────────────────────────────────────
    {"name": "Azalea", "scientific_name": "Rhododendron sp.",
     "fam": "Ericaceae", "shape": "trumpet", "colors": ["pink","red","white","purple","orange"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Spring Bloomer","Massed Display","Colorful"]},
    {"name": "Rhododendron", "scientific_name": "Rhododendron sp.",
     "fam": "Ericaceae", "shape": "trumpet", "colors": ["pink","red","white","purple","yellow"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Large Blooms","Spring Bloomer","Shade Tolerant"]},
    {"name": "Wisteria (Purple)", "scientific_name": "Wisteria sinensis",
     "fam": "Fabaceae", "shape": "clustered", "colors": ["purple","white","pink"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Cascading","Fragrant","Dramatic"]},
    {"name": "Bougainvillea (Global)", "scientific_name": "Bougainvillea spectabilis",
     "fam": "Nyctaginaceae", "shape": "clustered", "colors": ["pink","purple","red","orange","white","magenta"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Drought Tolerant","Colorful","Tropical"]},
    {"name": "Passion Flower", "scientific_name": "Passiflora sp.",
     "fam": "Passifloraceae", "shape": "star", "colors": ["purple","blue","white"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Exotic","Complex Flower","Climber"]},
    {"name": "Hibiscus (Chinese Rose)", "scientific_name": "Hibiscus rosa-sinensis",
     "fam": "Malvaceae", "shape": "cup", "colors": ["red","pink","yellow","white","orange"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Tropical","Easy Care","Large Blooms"]},
    {"name": "Bird of Paradise (Global)", "scientific_name": "Strelitzia reginae",
     "fam": "Strelitziaceae", "shape": "spike", "colors": ["orange","blue"],
     "bloom": "tropical_spike", "habit": "shrub", "tags": ["Exotic","Bold","Tropical"]},
    {"name": "Anthurium (Global)", "scientific_name": "Anthurium andraeanum",
     "fam": "Araceae", "shape": "spathe", "colors": ["red","pink","white","purple","orange"],
     "bloom": "tropical_spike", "habit": "shrub", "tags": ["Long Lasting","Exotic","Tropical"]},
    {"name": "Gardenia", "scientific_name": "Gardenia jasminoides",
     "fam": "Rubiaceae", "shape": "rose", "colors": ["white"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Fragrant","Pure White","Waxy Petals"]},
    {"name": "Protea", "scientific_name": "Protea cynaroides",
     "fam": "Proteaceae", "shape": "daisy", "colors": ["pink","red","white","yellow"],
     "bloom": "shrub_flower", "habit": "shrub", "tags": ["Exotic","Architectural","South African"]},
    {"name": "Strelitzia (White)", "scientific_name": "Strelitzia nicolai",
     "fam": "Strelitziaceae", "shape": "spike", "colors": ["white","blue"],
     "bloom": "tropical_spike", "habit": "tree", "tags": ["Giant","Tropical","Dramatic"]},
    {"name": "Lotus (Global)", "scientific_name": "Nelumbo nucifera",
     "fam": "Nelumbonaceae", "shape": "lily", "colors": ["pink","white","yellow"],
     "bloom": "aquatic_flower", "habit": "aquatic", "tags": ["Aquatic","Sacred","Fragrant"]},
    {"name": "Water Lily (Global)", "scientific_name": "Nymphaea sp.",
     "fam": "Nymphaeaceae", "shape": "lily", "colors": ["white","pink","yellow","purple"],
     "bloom": "aquatic_flower", "habit": "aquatic", "tags": ["Aquatic","Floating","Beautiful"]},
    {"name": "Bleeding Heart", "scientific_name": "Lamprocapnos spectabilis",
     "fam": "Papaveraceae", "shape": "tubular", "colors": ["pink","white"],
     "bloom": "shrub_flower", "habit": "herb", "tags": ["Arching Stems","Unique Shape","Shade Loving"]},
    {"name": "Sweet Pea", "scientific_name": "Lathyrus odoratus",
     "fam": "Fabaceae", "shape": "clustered", "colors": ["purple","pink","white","red","blue"],
     "bloom": "vine_flower", "habit": "vine", "tags": ["Fragrant","Climber","Cottage Garden"]},
]

# Build name index for fast lookup (name + scientific name → entry)
_KNOWN_PLANT_VISUALS: dict[str, dict] = {}
for _gf in _GLOBAL_FLOWERS:
    _KNOWN_PLANT_VISUALS[_gf["name"].lower()] = _gf
    _KNOWN_PLANT_VISUALS[_gf["scientific_name"].lower()] = _gf
# Also index Malaysian plants from _VISUAL so scanned Malaysian plants resolve correctly
for _vname, _vdata in _VISUAL.items():
    key = _vname.lower()
    if key not in _KNOWN_PLANT_VISUALS:
        _KNOWN_PLANT_VISUALS[key] = _vdata

# Extended shape relations (includes "cup")
_RELATED_SHAPES_V2: dict[str, set] = {
    "trumpet":   {"tubular", "lily", "cup"},
    "tubular":   {"trumpet", "cup"},
    "cup":       {"lily", "rose", "trumpet"},
    "lily":      {"trumpet", "cup"},
    "rose":      {"cup", "lily"},
    "daisy":     {"clustered", "star"},
    "clustered": {"daisy", "star", "spike"},
    "star":      {"clustered", "daisy"},
    "spike":     {"clustered"},
    "orchid":    set(),
    "spathe":    set(),
}
