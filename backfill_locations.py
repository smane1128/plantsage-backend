"""Backfill all scan_history records with updated location overrides."""
import sqlite3, json, sys
sys.path.insert(0, ".")
from services.cultivation_service import get_location_override

conn = sqlite3.connect("myplants.db")
c = conn.cursor()
c.execute("SELECT id, plant_name, scientific_name, details FROM scan_history")
rows = c.fetchall()

updated = 0
for row_id, plant_name, sci_name, details_json in rows:
    if not details_json:
        continue
    result = json.loads(details_json)

    override = get_location_override(plant_name or "", sci_name or "")
    if not override:
        print(f"  SKIP {row_id} {plant_name}: no override")
        continue

    suitability = result.setdefault("suitability", {})
    best_loc = suitability.setdefault("best_location", {})
    # Clear stale conditional dict before reapplying
    best_loc.pop("conditional", None)

    conditional = {}
    for loc, val in override.items():
        if isinstance(val, bool):
            best_loc[loc] = val
        elif isinstance(val, str) and val.startswith("conditional:"):
            best_loc[loc] = False
            conditional[loc] = val[len("conditional:"):]
    if conditional:
        best_loc["conditional"] = conditional

    c.execute("UPDATE scan_history SET details=? WHERE id=?", (json.dumps(result), row_id))
    cond_keys = list(conditional.keys())
    print(f"  {row_id} {plant_name}: balcony={best_loc.get('balcony')} porch={best_loc.get('porch')} conditional={cond_keys}")
    updated += 1

conn.commit()
conn.close()
print(f"\nDone. Updated {updated} / {len(rows)} records.")
