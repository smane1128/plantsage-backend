"""
Centralized plant display rules engine for PlantSage.

Single source of truth for deciding which UI sections are shown or hidden
based on a plant's cultivation category, suitability score, and recommendation.

Display modes
-------------
recommended       Score >= 61 OR recommendation in (Recommended, Highly Recommended)
                  → Show everything

challenging       Score 31–60 OR recommendation == Consider Carefully
                  OR cultivation_category == advanced_collector
                  → Show everything + warning banner

not_recommended   Score <= 30 OR recommendation == Not Recommended
                  OR (malaysia_suitable == False AND score < 40)
                  → Hide: watering, maintenance, monthly cost, garden fit,
                           add-to-garden button, cultivation advice
                  → Show: reason not recommended, pet safety,
                           Malaysian alternatives

botanical_only    cultivation_category == botanical_only OR is_special_plant
                  → Hide: score, cultivation, maintenance, watering,
                           pricing, add-to-garden, similar plants
                  → Show: habitat, conservation status, educational facts,
                           Malaysian alternatives

UI Rules
--------
recommended     : show all sections
challenging     : show all sections + warning banner
not_recommended : hide [watering, maintenance, monthly_cost, garden_fit,
                        add_to_garden, cultivation_advice]
                  show [reason_not_recommended, pet_safety, malaysia_alternatives]
botanical_only  : hide [score, cultivation, maintenance, watering, pricing,
                        add_to_garden, similar_plants]
                  show [habitat, conservation_status, educational_facts,
                        malaysia_alternatives]
"""
from __future__ import annotations

# ── Display mode constants ────────────────────────────────────────────────────
RECOMMENDED     = "recommended"
CHALLENGING     = "challenging"
NOT_RECOMMENDED = "not_recommended"
BOTANICAL_ONLY  = "botanical_only"

# Sections that each mode hides.  The UI reads this to build its conditional widget tree.
HIDDEN_SECTIONS: dict[str, set[str]] = {
    RECOMMENDED: set(),
    CHALLENGING: set(),
    NOT_RECOMMENDED: {
        "watering_schedule",
        "maintenance_level",
        "monthly_cost",
        "garden_fit",
        "add_to_garden_button",
        "cultivation_advice",
    },
    BOTANICAL_ONLY: {
        "score",
        "cultivation",
        "maintenance_level",
        "watering_schedule",
        "pricing",
        "add_to_garden_button",
        "similar_plants",
    },
}

# Sections that each mode shows (explicitly required).
SHOWN_SECTIONS: dict[str, set[str]] = {
    RECOMMENDED: {
        "score", "cultivation", "maintenance_level", "watering_schedule",
        "pricing", "add_to_garden_button", "similar_plants", "pet_safety",
        "malaysia_alternatives", "garden_fit", "cultivation_advice",
    },
    CHALLENGING: {
        "score", "cultivation", "maintenance_level", "watering_schedule",
        "pricing", "add_to_garden_button", "similar_plants", "pet_safety",
        "malaysia_alternatives", "garden_fit", "cultivation_advice",
        "warning_banner",
    },
    NOT_RECOMMENDED: {
        "reason_not_recommended",
        "pet_safety",
        "malaysia_alternatives",
    },
    BOTANICAL_ONLY: {
        "habitat",
        "conservation_status",
        "educational_facts",
        "malaysia_alternatives",
    },
}


def get_display_mode(plant_data: dict) -> str:
    """Compute the display mode for a plant response dict.

    Decision tree (evaluated top to bottom, first match wins):
        1. botanical_only  — cultivation_category or is_special_plant
        2. botanical_only  — gardenability_score == 0
        3. not_recommended — gardenability_score <= 15
        4. not_recommended — recommendation == 'Not Recommended'
        5. not_recommended — malaysia_suitable == False AND score < 40
        6. challenging     — cultivation_category == 'advanced_collector'
        7. challenging     — recommendation == 'Consider Carefully'
        8. challenging     — gardenability_score in [31, 60]
        9. recommended     — default

    Parameters
    ----------
    plant_data : dict
        The full plant response dict as returned by the identify endpoint.

    Returns
    -------
    str — one of: "recommended" | "challenging" | "not_recommended" | "botanical_only"
    """
    cult_cat   = (plant_data.get("cultivation_category") or "").lower()
    is_special = bool(plant_data.get("special_plant", False))
    score      = int(plant_data.get("gardenability_score") or 0)
    rec        = (plant_data.get("purchase_decision") or {}).get("recommendation", "")
    suit       = plant_data.get("suitability") or {}
    malaysia_suitable = suit.get("malaysia_suitable")
    score_band = plant_data.get("score_band") or {}

    # 1 & 2: Botanical / impossible-to-cultivate
    if cult_cat == "botanical_only" or is_special or score == 0:
        return BOTANICAL_ONLY

    # 3: Score below meaningful threshold → not recommended
    if score <= 15:
        return NOT_RECOMMENDED

    # 4: Explicit AI recommendation
    if rec == "Not Recommended":
        return NOT_RECOMMENDED

    # 5: Not suitable for Malaysia with a low score
    if malaysia_suitable is False and score < 40:
        return NOT_RECOMMENDED

    # 6: Advanced collector plants → always challenging
    if cult_cat == "advanced_collector":
        return CHALLENGING

    # 7: Explicit AI recommendation
    if rec == "Consider Carefully":
        return CHALLENGING

    # 8: Score band check
    if score <= 60:
        return CHALLENGING

    # 9: Default
    return RECOMMENDED


def get_ui_rules(mode: str) -> dict:
    """Return a dict describing which sections to hide/show for the given mode.

    Returns
    -------
    dict with keys:
        mode          : str  — display mode string
        hidden        : list[str]  — section identifiers to hide
        shown         : list[str]  — section identifiers to show
        warning_banner: bool — whether to display a warning banner
        add_to_garden : bool — whether the add-to-garden button is shown
    """
    return {
        "mode":           mode,
        "hidden":         sorted(HIDDEN_SECTIONS.get(mode, set())),
        "shown":          sorted(SHOWN_SECTIONS.get(mode, set())),
        "warning_banner": mode == CHALLENGING,
        "add_to_garden":  mode in (RECOMMENDED, CHALLENGING),
    }
