"""
audit_scores.py — Complete score source audit for MyPlants backend.

Scans every scan_history record and reports:
  - Plant Name, DB suitability_score column, JSON gardenability_score,
    JSON purchase_decision.suitability_score, recommendation, score_band,
    malaysia_suitable, consistency status

Flags ALL mismatches and patches them in place.

Usage:
    cd C:\myplants\backend
    .\venv\Scripts\Activate.ps1
    python audit_scores.py
"""
from __future__ import annotations
import sys, os, json, sqlite3
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from services.cultivation_service import (
    get_cultivation_category,
    get_gardenability_score,
    get_score_band,
    is_special_plant,
)
import importlib
_enforce = importlib.import_module("routes.identify")._enforce_score_consistency

DB_PATH = os.path.join(os.path.dirname(__file__), "myplants.db")
conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

cur.execute("""
    SELECT id, plant_name, scientific_name, recommendation, suitability_score, details
    FROM scan_history
    ORDER BY id
""")
rows = cur.fetchall()

print("=" * 90)
print(f"{'ID':>4}  {'Plant':<28}  {'ColScore':>8}  {'JSON_GS':>7}  {'JSON_PS':>7}  {'Band':<18}  {'Status'}")
print("=" * 90)

PASS  = "OK"
FAIL  = "MISMATCH"
PATCH = "PATCHED"

patched = 0
ok_count = 0
errors = []

for row in rows:
    rid        = row["id"]
    name       = row["plant_name"] or "?"
    col_score  = row["suitability_score"]
    col_rec    = row["recommendation"] or ""
    raw        = row["details"]

    if not raw:
        print(f"{rid:>4}  {name:<28}  {'NO DETAILS':>38}")
        errors.append(f"id={rid} {name!r}: no details JSON")
        continue

    try:
        d = json.loads(raw)
    except Exception as e:
        print(f"{rid:>4}  {name:<28}  JSON PARSE ERROR: {e}")
        errors.append(f"id={rid} {name!r}: JSON parse error: {e}")
        continue

    json_gs  = d.get("gardenability_score")
    json_ps  = d.get("purchase_decision", {}).get("suitability_score")
    json_rec = d.get("purchase_decision", {}).get("recommendation", "")
    json_mal = d.get("suitability", {}).get("malaysia_suitable")
    json_cat = d.get("cultivation_category", "?")
    json_sb  = d.get("score_band", {})
    json_sb_short = json_sb.get("short_label", "?") if json_sb else "?"

    # Consistency check: col == json_gs, band present, band matches json_gs
    issues = []
    if col_score is None:
        issues.append("col_score=None")
    if json_gs is None:
        issues.append("json_gs=None")
    if col_score is not None and json_gs is not None and col_score != json_gs:
        issues.append(f"col={col_score}!=json_gs={json_gs}")
    if not json_sb:
        issues.append("no score_band")
    if json_gs is not None:
        expected_band = get_score_band(json_gs)["short_label"]
        if json_sb_short != expected_band:
            issues.append(f"band={json_sb_short!r}!={expected_band!r}")

    status = FAIL if issues else PASS

    band_display = json_sb_short if json_sb else f"(fallback:{get_score_band(json_gs or 0)['short_label']})"
    print(f"{rid:>4}  {name:<28}  {str(col_score):>8}  {str(json_gs):>7}  {str(json_ps):>7}  "
          f"{band_display:<18}  {status}"
          + (f"  [{', '.join(issues)}]" if issues else ""))

    if issues:
        # Re-run full enforcement on the record
        _enforce(d, name)
        new_gs  = d["gardenability_score"]
        new_rec = d["purchase_decision"]["recommendation"]
        new_band = d.get("score_band", {}).get("short_label", "?")

        cur.execute(
            "UPDATE scan_history SET details=?, suitability_score=?, recommendation=? WHERE id=?",
            (json.dumps(d), new_gs, new_rec, rid)
        )
        patched += 1
        print(f"       -> PATCHED: gs={new_gs}  col={new_gs}  band={new_band!r}  rec={new_rec!r}")
        errors.append(f"id={rid} {name!r}: {', '.join(issues)} -> fixed to gs={new_gs}")
    else:
        ok_count += 1

conn.commit()
conn.close()

print("=" * 90)
print(f"Total: {len(rows)} records  OK: {ok_count}  Patched: {patched}")
if errors:
    print()
    print("Issues found and fixed:")
    for e in errors:
        print(f"  {e}")
print()
print("Score source report:")
print("  Dashboard badge : GET /history -> s.suitability_score (DB column)")
print("  Detail page     : GET /history -> s.details JSON -> gardenability_score")
print("  Both must equal the enforced gardenability_score.")
print()
print("Done.")
