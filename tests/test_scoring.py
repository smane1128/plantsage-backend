"""
Automated validation tests for the plant scoring system.

Verifies:
  1. get_gardenability_score()   → correct canonical band for every category/difficulty
  2. get_score_band()            → correct label for every score boundary
  3. _enforce_score_consistency() → hard rules:
       Rule 1: cold-dormancy         → score ≤ 15, Not Recommended
       Rule 2: malaysia_suitable=False → score ≤ 20, Not Recommended
       Rule 3: score ↔ recommendation always agree per new bands
       Rule 4: special / botanical-only plants → score ≤ 9, Not Recommended
  4. suitability_score column always == gardenability_score after enforcement
  5. Plant-specific integration tests: Crocus, Rafflesia, Rose,
       Firecracker Flower, Queen of the Night
  6. Score modification audit covering all 8 write paths

Score band reference (canonical):
  81-100  Highly Recommended
  61-80   Recommended
  41-60   Moderate
  21-40   Challenging
  10-20   Not Recommended
   0-9    Botanical Only

Run:
    cd C:\\myplants\\backend
    .\\venv\\Scripts\\Activate.ps1
    python -m pytest tests/test_scoring.py -v
"""
from __future__ import annotations
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from services.cultivation_service import (
    get_gardenability_score,
    get_score_band,
    _SCORE_BANDS,
    get_cultivation_category,
    is_special_plant,
)

import importlib
identify_mod = importlib.import_module("routes.identify")
_enforce_score_consistency = identify_mod._enforce_score_consistency


# ---------------------------------------------------------------------------
# 1. Score values fall inside the correct canonical band
# ---------------------------------------------------------------------------
class TestGetGardenabilityScore:
    CASES = [
        ("botanical_only",     "",       "Botanical Only",       "Rafflesia / parasitic"),
        ("advanced_collector", "hard",   "Challenging",          "Venus flytrap hard"),
        ("advanced_collector", "medium", "Challenging",          "Venus flytrap medium"),
        ("advanced_collector", "",       "Challenging",          "Venus flytrap easy"),
        ("specialty_garden",   "hard",   "Moderate",             "Jade vine hard"),
        ("specialty_garden",   "medium", "Moderate",             "Jade vine medium"),
        ("specialty_garden",   "",       "Moderate",             "Jade vine easy"),
        ("common_garden",      "hard",   "Recommended",          "Rose hard"),
        ("common_garden",      "medium", "Recommended",          "Rose medium"),
        ("common_garden",      "",       "Highly Recommended",   "Bougainvillea easy"),
    ]

    @pytest.mark.parametrize("category,difficulty,expected_band,label", CASES)
    def test_score_band(self, category, difficulty, expected_band, label):
        score = get_gardenability_score(category, difficulty)
        band  = get_score_band(score)
        assert band["short_label"] == expected_band, (
            f"{label}: score={score} expected '{expected_band}' got '{band['short_label']}'"
        )

    def test_botanical_only_0_to_9(self):
        assert 0 <= get_gardenability_score("botanical_only") <= 9

    def test_advanced_collector_21_to_40(self):
        for d in ("hard", "medium", ""):
            s = get_gardenability_score("advanced_collector", d)
            assert 21 <= s <= 40, f"advanced_collector/{d!r}: {s}"

    def test_specialty_garden_41_to_60(self):
        for d in ("hard", "medium", ""):
            s = get_gardenability_score("specialty_garden", d)
            assert 41 <= s <= 60, f"specialty_garden/{d!r}: {s}"

    def test_common_garden_hard_medium_61_to_80(self):
        for d in ("hard", "medium"):
            s = get_gardenability_score("common_garden", d)
            assert 61 <= s <= 80, f"common_garden/{d!r}: {s}"

    def test_common_garden_easy_81_to_100(self):
        s = get_gardenability_score("common_garden", "")
        assert 81 <= s <= 100, f"common_garden easy: {s}"


# ---------------------------------------------------------------------------
# 2. get_score_band() boundaries
# ---------------------------------------------------------------------------
class TestGetScoreBand:
    BOUNDARY_CASES = [
        (0,   "Botanical Only"),
        (5,   "Botanical Only"),
        (9,   "Botanical Only"),
        (10,  "Not Recommended"),
        (15,  "Not Recommended"),
        (20,  "Not Recommended"),
        (21,  "Challenging"),
        (30,  "Challenging"),
        (40,  "Challenging"),
        (41,  "Moderate"),
        (50,  "Moderate"),
        (60,  "Moderate"),
        (61,  "Recommended"),
        (70,  "Recommended"),
        (80,  "Recommended"),
        (81,  "Highly Recommended"),
        (90,  "Highly Recommended"),
        (100, "Highly Recommended"),
    ]

    @pytest.mark.parametrize("score,expected_short", BOUNDARY_CASES)
    def test_boundary(self, score, expected_short):
        band = get_score_band(score)
        assert band["short_label"] == expected_short, (
            f"score={score}: expected '{expected_short}' got '{band['short_label']}'"
        )

    def test_band_has_all_keys(self):
        for key in ("label", "short_label", "min", "max"):
            assert key in get_score_band(72)

    def test_no_gap_or_overlap(self):
        bands_sorted = sorted(_SCORE_BANDS, key=lambda b: b[0])
        assert bands_sorted[0][0] == 0
        assert bands_sorted[-1][1] == 100
        for i in range(len(bands_sorted) - 1):
            assert bands_sorted[i+1][0] == bands_sorted[i][1] + 1, (
                f"Gap: {bands_sorted[i]} -> {bands_sorted[i+1]}"
            )


# ---------------------------------------------------------------------------
# 3. _enforce_score_consistency -- hard validation rules
# ---------------------------------------------------------------------------
def _make_result(*, score, rec, malaysia=True, description="", seasonal="", challenges=None):
    return {
        "gardenability_score": score,
        "identification": {"plant_name": "TestPlant", "description": description},
        "purchase_decision": {
            "suitability_score": score,
            "recommendation": rec,
            "advantages": [],
            "challenges": challenges or [],
        },
        "suitability": {"malaysia_suitable": malaysia},
        "maintenance": {"seasonal_care": seasonal},
    }


class TestEnforceScoreConsistency:

    def _enforce(self, result):
        _enforce_score_consistency(result, result["identification"]["plant_name"])
        return result

    def test_suitability_score_equals_gardenability_score(self):
        for r in [
            _make_result(score=5,  rec="Not Recommended"),
            _make_result(score=15, rec="Not Recommended"),
            _make_result(score=30, rec="Consider Carefully"),
            _make_result(score=65, rec="Recommended"),
            _make_result(score=85, rec="Highly Recommended"),
        ]:
            self._enforce(r)
            assert r["gardenability_score"] == r["purchase_decision"]["suitability_score"]

    # Rule 2
    def test_rule2_malaysia_false_capped_at_20(self):
        r = _make_result(score=75, rec="Recommended", malaysia=False)
        self._enforce(r)
        assert r["gardenability_score"] <= 20
        assert r["purchase_decision"]["recommendation"] == "Not Recommended"

    def test_rule2_crocus_bug_30_not_recommended_malaysia_false(self):
        r = _make_result(score=30, rec="Not Recommended", malaysia=False)
        self._enforce(r)
        assert r["gardenability_score"] <= 20
        assert r["purchase_decision"]["recommendation"] == "Not Recommended"
        assert r["score_band"]["short_label"] != "Challenging"

    # Rule 3
    def test_rule3_not_recommended_caps_at_20(self):
        r = _make_result(score=95, rec="Not Recommended")
        self._enforce(r)
        assert r["gardenability_score"] <= 20

    def test_rule3_consider_carefully_caps_at_40(self):
        r = _make_result(score=80, rec="Consider Carefully")
        self._enforce(r)
        assert r["gardenability_score"] <= 40

    def test_rule3_recommended_caps_at_80(self):
        r = _make_result(score=95, rec="Recommended")
        self._enforce(r)
        assert r["gardenability_score"] <= 80

    # Rule 4
    def test_rule4_rec_matches_score(self):
        cases = [
            (_make_result(score=5,  rec="Not Recommended"),    "Not Recommended"),
            (_make_result(score=20, rec="Not Recommended"),    "Not Recommended"),
            (_make_result(score=30, rec="Consider Carefully"), "Consider Carefully"),
            (_make_result(score=40, rec="Consider Carefully"), "Consider Carefully"),
            (_make_result(score=65, rec="Recommended"),        "Recommended"),
            (_make_result(score=80, rec="Recommended"),        "Recommended"),
            (_make_result(score=85, rec="Highly Recommended"), "Highly Recommended"),
        ]
        for r, expected in cases:
            self._enforce(r)
            actual = r["purchase_decision"]["recommendation"]
            assert actual == expected

    # Rule 1
    def test_rule1_cold_dormancy_seasonal(self):
        r = _make_result(score=80, rec="Recommended",
                         seasonal="requires cold dormancy period and chilling hours")
        self._enforce(r)
        assert r["gardenability_score"] <= 15
        assert r["purchase_decision"]["recommendation"] == "Not Recommended"

    def test_rule1_cool_temperature_keyword(self):
        r = _make_result(score=65, rec="Recommended",
                         description="grows best in cool temperature conditions; spring bulb")
        self._enforce(r)
        assert r["gardenability_score"] <= 15
        assert r["purchase_decision"]["recommendation"] == "Not Recommended"

    def test_rule1_spring_bulb_keyword(self):
        r = _make_result(score=70, rec="Recommended",
                         seasonal="spring bulb requiring dry dormancy in summer")
        self._enforce(r)
        assert r["gardenability_score"] <= 15

    # score_band injection
    def test_score_band_injected(self):
        r = _make_result(score=72, rec="Recommended")
        self._enforce(r)
        assert "score_band" in r
        assert r["score_band"]["short_label"] == "Recommended"

    def test_score_band_challenging(self):
        r = _make_result(score=30, rec="Consider Carefully")
        self._enforce(r)
        assert r["score_band"]["short_label"] == "Challenging"

    def test_score_band_moderate(self):
        r = _make_result(score=52, rec="Recommended")
        self._enforce(r)
        assert r["score_band"]["short_label"] == "Moderate"

    def test_score_band_highly_recommended(self):
        r = _make_result(score=85, rec="Highly Recommended")
        self._enforce(r)
        assert r["score_band"]["short_label"] == "Highly Recommended"

    def test_rose_passes_unchanged(self):
        r = _make_result(score=72, rec="Recommended", malaysia=True)
        self._enforce(r)
        assert r["gardenability_score"] == 72
        assert r["purchase_decision"]["recommendation"] == "Recommended"

    def test_highly_recommended_passes_unchanged(self):
        r = _make_result(score=85, rec="Highly Recommended", malaysia=True)
        self._enforce(r)
        assert r["gardenability_score"] == 85
        assert r["purchase_decision"]["recommendation"] == "Highly Recommended"


# ---------------------------------------------------------------------------
# 4. Exhaustive: every score 0-100 has a valid band
# ---------------------------------------------------------------------------
class TestScoreConsistencyExhaustive:
    def test_all_scores_have_band(self):
        for s in range(101):
            band = get_score_band(s)
            assert band["label"] and band["short_label"]
            assert 0 <= band["min"] <= s <= band["max"] <= 100


# ---------------------------------------------------------------------------
# 5. Specific plant integration tests
# ---------------------------------------------------------------------------
class TestSpecificPlants:
    def _pipeline(self, plant_name, sci_name, description="", difficulty="",
                  malaysia=True, seasonal="", challenges=None,
                  ai_rec="Recommended", ai_score=75):
        category   = get_cultivation_category(plant_name, sci_name, description, difficulty)
        base_score = get_gardenability_score(category, difficulty)
        special    = is_special_plant(plant_name, sci_name, category)
        result = {
            "gardenability_score": base_score,
            "cultivation_category": category,
            "special_plant": special,
            "identification": {"plant_name": plant_name, "description": description},
            "purchase_decision": {
                "suitability_score": ai_score,
                "recommendation": ai_rec,
                "advantages": [],
                "challenges": challenges or [],
            },
            "suitability": {"malaysia_suitable": malaysia},
            "maintenance": {"seasonal_care": seasonal, "difficulty": difficulty},
        }
        _enforce_score_consistency(result, plant_name)
        return result

    # -- Crocus --
    def test_crocus_cold_dormancy_plus_malaysia_false(self):
        result = self._pipeline(
            plant_name="Crocus", sci_name="Crocus sativus",
            description="spring flowering bulb requiring cool temperature and dry dormancy period",
            malaysia=False,
            seasonal="requires cool growing season and bulb dormancy in summer",
            ai_rec="Not Recommended", ai_score=30,
        )
        assert result["gardenability_score"] <= 15
        assert result["purchase_decision"]["recommendation"] == "Not Recommended"
        assert result["score_band"]["short_label"] != "Challenging"

    def test_crocus_malaysia_false_alone(self):
        result = self._pipeline(
            plant_name="Crocus", sci_name="Crocus sativus",
            malaysia=False, ai_rec="Not Recommended", ai_score=30,
        )
        assert result["gardenability_score"] <= 20
        assert result["purchase_decision"]["recommendation"] == "Not Recommended"

    def test_crocus_dashboard_bug_fixed(self):
        r = _make_result(score=30, rec="Not Recommended", malaysia=False)
        _enforce_score_consistency(r, "Crocus")
        assert r["gardenability_score"] <= 20
        assert r["score_band"]["short_label"] != "Challenging"

    # -- Rafflesia --
    def test_rafflesia_botanical_only_category(self):
        cat = get_cultivation_category(
            "Rafflesia", "Rafflesia arnoldii",
            "obligate endoparasite on Tetrastigma, no roots no stems no leaves"
        )
        assert cat == "botanical_only"

    def test_rafflesia_score_le_9(self):
        result = self._pipeline(
            plant_name="Rafflesia", sci_name="Rafflesia arnoldii",
            description="obligate endoparasite on Tetrastigma, no roots no stems",
            malaysia=False, ai_rec="Not Recommended", ai_score=5,
        )
        assert result["gardenability_score"] <= 9
        assert result["score_band"]["short_label"] == "Botanical Only"
        assert result["special_plant"] is True

    def test_rafflesia_is_special(self):
        assert is_special_plant("Rafflesia", "Rafflesia arnoldii", "botanical_only") is True

    # -- Rose --
    def test_rose_recommended_61_to_80(self):
        result = self._pipeline(
            plant_name="Rose", sci_name="Rosa spp.", difficulty="medium",
            malaysia=True, ai_rec="Recommended", ai_score=72,
        )
        s = result["gardenability_score"]
        assert 61 <= s <= 80, f"Rose medium: score={s}"
        assert result["score_band"]["short_label"] == "Recommended"

    def test_rose_easy_highly_recommended(self):
        result = self._pipeline(
            plant_name="Rose", sci_name="Rosa hybrid",
            malaysia=True, ai_rec="Highly Recommended", ai_score=85,
        )
        assert result["gardenability_score"] >= 81
        assert result["score_band"]["short_label"] == "Highly Recommended"

    # -- Firecracker Flower --
    def test_firecracker_flower_recommended_or_better(self):
        result = self._pipeline(
            plant_name="Firecracker Flower", sci_name="Crossandra infundibuliformis",
            malaysia=True, ai_rec="Highly Recommended", ai_score=85,
        )
        assert result["gardenability_score"] >= 61
        assert result["score_band"]["short_label"] in ("Recommended", "Highly Recommended")

    def test_firecracker_flower_not_capped_by_malaysia(self):
        result = self._pipeline(
            plant_name="Firecracker Flower", sci_name="Crossandra infundibuliformis",
            malaysia=True, ai_rec="Recommended", ai_score=72,
        )
        assert result["gardenability_score"] > 20

    # -- Queen of the Night --
    def test_queen_of_the_night_moderate_or_better(self):
        result = self._pipeline(
            plant_name="Queen of the Night", sci_name="Epiphyllum oxypetalum",
            malaysia=True, ai_rec="Recommended", ai_score=72,
        )
        assert result["gardenability_score"] >= 41
        assert result["score_band"]["short_label"] in ("Moderate", "Recommended", "Highly Recommended")

    def test_queen_of_the_night_not_special(self):
        cat = get_cultivation_category("Queen of the Night", "Epiphyllum oxypetalum", "", "medium")
        assert cat != "botanical_only"
        assert is_special_plant("Queen of the Night", "Epiphyllum oxypetalum", cat) is False


# ---------------------------------------------------------------------------
# 6. Score modification audit
# ---------------------------------------------------------------------------
class TestScoreModificationAudit:
    def test_crocus_exact_bug_scenario(self):
        r = _make_result(score=30, rec="Not Recommended", malaysia=False)
        _enforce_score_consistency(r, "Crocus")
        assert r["gardenability_score"] <= 20
        assert r["score_band"]["short_label"] != "Challenging"

    def test_malaysia_cap_at_20_for_all_starting_scores(self):
        for init in (5, 10, 20, 25, 30, 40, 50, 75, 95, 100):
            r = _make_result(score=init, rec="Recommended", malaysia=False)
            _enforce_score_consistency(r, f"test init={init}")
            assert r["gardenability_score"] <= 20, (
                f"init={init}: final={r['gardenability_score']} exceeded cap 20"
            )

    def test_score_band_contains_final_score(self):
        for r in [
            _make_result(score=5,  rec="Not Recommended"),
            _make_result(score=20, rec="Not Recommended"),
            _make_result(score=30, rec="Consider Carefully"),
            _make_result(score=55, rec="Recommended"),
            _make_result(score=72, rec="Recommended"),
            _make_result(score=85, rec="Highly Recommended"),
            _make_result(score=30, rec="Not Recommended", malaysia=False),
        ]:
            _enforce_score_consistency(r, "audit")
            s = r["gardenability_score"]
            b = r["score_band"]
            assert b["min"] <= s <= b["max"], (
                f"score={s} outside band [{b['min']},{b['max']}] '{b['short_label']}'"
            )

    def test_price_suppression_threshold_aligns_with_bands(self):
        for s in (0, 5, 9, 10, 15, 20):
            band = get_score_band(s)
            assert band["short_label"] in ("Botanical Only", "Not Recommended")
        assert get_score_band(21)["short_label"] == "Challenging"
