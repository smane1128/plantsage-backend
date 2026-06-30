"""
PlantSage Post-Deployment Validation Script
Tests: pet safety, confidence logic, care schedule, regression checks
"""
import sys
import os
import json
from unittest.mock import MagicMock

# Mock openai so openai_service.py imports cleanly without the package installed
sys.modules['openai'] = MagicMock()
sys.modules['dotenv'] = MagicMock()
# Stub load_dotenv
import types
dotenv_mod = types.ModuleType('dotenv')
dotenv_mod.load_dotenv = lambda *a, **k: None
sys.modules['dotenv'] = dotenv_mod

os.chdir(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"

results = []

def check(category, test_name, condition, expected="", actual="", note=""):
    status = PASS if condition else FAIL
    results.append({
        "category": category,
        "test": test_name,
        "status": status,
        "expected": expected,
        "actual": actual,
        "note": note,
    })
    icon = "✅" if status == PASS else "❌"
    print(f"  {icon} {test_name}: {actual or expected} {('— ' + note) if note else ''}")

def warn(category, test_name, note):
    results.append({"category": category, "test": test_name, "status": WARN, "note": note})
    print(f"  ⚠️  {test_name}: {note}")


# ═══════════════════════════════════════════════════════════════
# 1. PET SAFETY
# ═══════════════════════════════════════════════════════════════
print("\n── 1. PET SAFETY ──────────────────────────────────────────")
from services.pet_safety_service import lookup_pet_safety

pet_tests = [
    # (sci_name, common_name, expected_status, expected_source_prefix)
    ("hibiscus rosa-sinensis", "Hibiscus",        "safe",    "database"),
    ("etlingera elatior",      "Torch Ginger",    "safe",    "database"),
    ("curcuma longa",          "Turmeric",        "safe",    "database"),
    ("zingiber officinale",    "Ginger",          "safe",    "database"),
    ("alocasia macrorrhizos",  "Alocasia",        "caution", "database"),
    ("monstera deliciosa",     "Monstera",        "caution", "database"),
    ("dracaena trifasciata",   "Snake Plant",     "caution", "database"),
    ("cordyline fruticosa",    "Cordyline/Ti",    "caution", "database"),
    ("canna indica",           "Canna Lily",      "safe",    "database"),
    ("nerium oleander",        "Oleander",        "toxic",   "database"),
    ("lantana camara",         "Lantana",         "toxic",   "database"),
    ("cycas revoluta",         "Sago Palm",       "toxic",   "database"),
    ("epipremnum aureum",      "Pothos",          "caution", "database"),
    ("adenium obesum",         "Desert Rose",     "toxic",   "database"),
    ("allamanda cathartica",   "Allamanda",       "toxic",   "database"),
    # Alias-only lookups (no sci name)
    ("", "torch ginger",      "safe",    "database"),
    ("", "turmeric",          "safe",    "database"),
    ("", "ginger",            "safe",    "database"),
    ("", "alocasia",          "caution", "database"),
    ("", "ti plant",          "caution", "database"),
    ("", "bunga kantan",      "safe",    "database"),
    ("", "kunyit",            "safe",    "database"),
    ("", "halia",             "safe",    "database"),
    ("", "sago palm",         "toxic",   "database"),
    ("", "desert rose",       "toxic",   "database"),
    ("", "lantana",           "toxic",   "database"),
]

for sci, com, exp_status, exp_source in pet_tests:
    r = lookup_pet_safety(sci, com)
    ok = r["status"] == exp_status and r["source"] == exp_source
    check("Pet Safety", com or sci,
          ok,
          f"status={exp_status} source={exp_source}",
          f"status={r['status']} source={r['source']}",
          r.get("symptoms","")[:60] if r["status"]!="unknown" else "NOT IN DB")


# ═══════════════════════════════════════════════════════════════
# 2. CONFIDENCE LOGIC
# ═══════════════════════════════════════════════════════════════
print("\n── 2. CONFIDENCE LOGIC ────────────────────────────────────")
from services.openai_service import _enforce_confidence

def make_result(plant_name, sci_name, confidence, image_features, possible_matches=None):
    return {
        "identification": {
            "plant_name": plant_name,
            "scientific_name": sci_name,
            "confidence_level": confidence,
            "image_features": image_features,
            "low_confidence_reason": "",
        },
        "possible_matches": possible_matches or [],
    }

# Leaf-identifiable plants should NOT be capped at 70
conf_tests = [
    # (plant, sci, confidence_in, features, should_cap, expected_max)
    ("Monstera",    "Monstera deliciosa", 90, ["fenestrated leaves","large tropical foliage"],                 False, 90),
    ("Snake Plant", "Dracaena trifasciata",85, ["sword-shaped leaves","distinctive variegation"],              False, 85),
    ("ZZ Plant",    "Zamioculcas zamiifolia",82, ["glossy compound leaves","succulent stems"],                 False, 82),
    ("Pandan",      "Pandanus amaryllifolius",88, ["strap-shaped leaves","spiral arrangement"],                False, 88),
    ("Lotus",       "Nelumbo nucifera",   87, ["large round leaves","aquatic","distinctive"],                  False, 87),
    # Generic tropical trees SHOULD still be capped
    ("Syzygium sp.","Syzygium aqueum",    85, ["leaves only","simple ovate leaves","no flowers"],             True,  60),
    ("Guava",       "Psidium guajava",    80, ["leaves only","no flowers","no fruit"],                        True,  60),
    # Generic shrub with no distinctive features — cap at 70
    ("Unknown shrub","Hibiscus mutabilis", 80, ["leaves","green foliage"],                                    True,  70),
]

for plant, sci, conf_in, features, should_cap, expected_max in conf_tests:
    r = make_result(plant, sci, conf_in, features)
    _enforce_confidence(r)
    conf_out = r["identification"]["confidence_level"]
    if should_cap:
        ok = conf_out <= expected_max
        check("Confidence", f"{plant} (cap expected)",
              ok, f"≤{expected_max}", str(conf_out))
    else:
        ok = conf_out == conf_in  # should be unchanged
        check("Confidence", f"{plant} (no cap expected)",
              ok, str(conf_in), str(conf_out))

# Possible matches cap test
print("  [Possible matches cap]")
r = make_result("Guava", "Psidium guajava", 65, ["leaves only"],
    possible_matches=[
        {"plant_name": "Water Apple", "scientific_name": "Syzygium samarangense", "confidence": 90, "distinguishing_note": "..."},
        {"plant_name": "Jambu Air",   "scientific_name": "Syzygium aqueum",        "confidence": 55, "distinguishing_note": "..."},
    ])
_enforce_confidence(r)
primary = r["identification"]["confidence_level"]
for m in r["possible_matches"]:
    mc = m["confidence"]
    ok = mc < primary
    check("Confidence", f"PossibleMatch '{m['plant_name']}' < primary({primary})",
          ok, f"<{primary}", str(mc))


# ═══════════════════════════════════════════════════════════════
# 3. CARE SCHEDULE
# ═══════════════════════════════════════════════════════════════
print("\n── 3. CARE SCHEDULE ───────────────────────────────────────")
from services.care_schedule_service import get_care_intervals, get_watering_interval

care_tests = [
    # (sci_name, common_name, expected_tasks_present, expected_tasks_absent, expected_source)
    ("mangifera indica",   "Mango",        ["fertilize","prune","pest_check"],  [],          "species_specific"),
    ("musa paradisiaca",   "Banana",       ["fertilize","pest_check"],           ["prune"],   "species_specific"),
    ("dendrobium",         "Orchid",       ["fertilize","pest_check"],           ["prune"],   "species_specific"),
    ("curcuma longa",      "Turmeric",     ["fertilize","pest_check"],           ["prune"],   "species_specific"),
    ("etlingera elatior",  "Torch Ginger", ["fertilize","prune","pest_check"],  [],          "species_specific"),
    ("psidium guajava",    "Guava",        ["fertilize","prune","pest_check"],  [],          "species_specific"),
    ("rosa",               "Rose",         ["fertilize","prune","pest_check"],  [],          "species_specific"),
    ("hibiscus rosa-sinensis", "Hibiscus", ["fertilize","prune","pest_check"],  [],          "species_specific"),
    ("helianthus annuus",  "Sunflower",    ["fertilize","pest_check"],           ["prune"],   "species_specific"),
]

for sci, com, expected_present, expected_absent, expected_src in care_tests:
    intervals = get_care_intervals("{}", "unknown", plant_name=com, scientific_name=sci)
    watering  = get_watering_interval("{}", "unknown", plant_name=com, scientific_name=sci)

    # Check source
    sources = set(v["source"] for v in intervals.values() if v)
    src_ok = expected_src in sources
    check("Care Schedule", f"{com} source={expected_src}", src_ok,
          expected_src, ", ".join(sources) if sources else "no tasks")

    # Check watering
    check("Care Schedule", f"{com} watering>0", watering > 0,
          ">0", str(watering))

    # Check tasks present
    for task in expected_present:
        present = task in intervals and intervals[task] is not None
        val = intervals.get(task)
        check("Care Schedule", f"{com} has {task}",
              present, "present",
              f"{val['interval_days']}d" if val else "None/missing")

    # Check tasks absent (intentionally skipped)
    for task in expected_absent:
        absent = task not in intervals or intervals[task] is None
        check("Care Schedule", f"{com} no {task} (correct)",
              absent, "absent/None",
              str(intervals.get(task)))


# ═══════════════════════════════════════════════════════════════
# 4. REGRESSION: Score consistency
# ═══════════════════════════════════════════════════════════════
print("\n── 4. REGRESSION ──────────────────────────────────────────")
from services.cultivation_service import get_gardenability_score, get_cultivation_category, get_score_band

score_tests = [
    ("Hibiscus",    "Hibiscus rosa-sinensis", "common_garden",    56, 100),
    ("Rose",        "Rosa indica",            "common_garden",    56, 100),
    ("Monstera",    "Monstera deliciosa",     "common_garden",    56, 100),
    ("Rafflesia",   "Rafflesia arnoldii",     "botanical_only",   0,  20),
    ("Tulip",       "Tulipa gesneriana",      "botanical_only",   0,  20),
]

for common, sci, exp_cat, score_min, score_max in score_tests:
    cat = get_cultivation_category(common, sci, "", "Easy")
    score = get_gardenability_score(cat, "Easy")
    band = get_score_band(score)
    cat_ok = cat == exp_cat
    score_ok = score_min <= score <= score_max
    check("Regression", f"{common} category={exp_cat}", cat_ok, exp_cat, cat)
    check("Regression", f"{common} score {score_min}-{score_max}", score_ok,
          f"{score_min}-{score_max}", str(score), band["label"])

# Pet safety: ensure previously working entries still work
reg_pet = [
    ("nerium oleander", "Oleander", "toxic"),
    ("hibiscus rosa-sinensis", "Hibiscus", "safe"),
    ("epipremnum aureum", "Pothos", "caution"),
]
for sci, com, exp in reg_pet:
    r = lookup_pet_safety(sci, com)
    check("Regression", f"Pet regression: {com}", r["status"] == exp, exp, r["status"])

# Care schedule regression: existing plants still work
reg_care = [
    ("rosa", "Rose",    "fertilize"),
    ("helianthus annuus", "Sunflower", "fertilize"),
    ("epipremnum aureum", "Pothos",    "fertilize"),
]
for sci, com, task in reg_care:
    intervals = get_care_intervals("{}", "unknown", plant_name=com, scientific_name=sci)
    ok = task in intervals and intervals[task] is not None
    check("Regression", f"Care regression: {com} has {task}", ok)


# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
print("\n═══════════════════════════════════════════════════════════")
passed = sum(1 for r in results if r["status"] == PASS)
failed = sum(1 for r in results if r["status"] == FAIL)
warned = sum(1 for r in results if r["status"] == WARN)
total  = len(results)

print(f"\nRESULTS: {passed}/{total} passed  |  {failed} failed  |  {warned} warnings\n")

if failed:
    print("FAILURES:")
    for r in results:
        if r["status"] == FAIL:
            print(f"  ❌ [{r['category']}] {r['test']}: expected={r.get('expected','')} actual={r.get('actual','')}")

# Write JSON for report generation
with open("validate_results.json", "w") as f:
    json.dump({"passed": passed, "failed": failed, "total": total, "results": results}, f, indent=2)

print("\nvalidate_results.json written.")
sys.exit(0 if failed == 0 else 1)
