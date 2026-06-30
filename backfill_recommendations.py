"""One-time script: backfill similar_flowers + malaysia_alternatives for all existing scan_history records."""
import sqlite3, json, sys
sys.path.insert(0, ".")
from services.recommendation_service import get_similar_plants, get_similar_flowers, get_malaysia_alternatives

conn = sqlite3.connect("myplants.db")
c = conn.cursor()
c.execute("SELECT id, plant_name, details FROM scan_history")
rows = c.fetchall()

updated = 0
for row_id, plant_name, details_json in rows:
    if not details_json:
        print(f"  SKIP {row_id} {plant_name}: no details")
        continue
    result = json.loads(details_json)
    flw = result.setdefault("flowering", {})

    flw["similar_plants"]        = get_similar_plants(result)
    flw["similar_flowers"]       = get_similar_flowers(result)
    flw["malaysia_alternatives"] = get_malaysia_alternatives(result)

    c.execute("UPDATE scan_history SET details=? WHERE id=?", (json.dumps(result), row_id))
    sf = len(flw["similar_flowers"])
    ma = len(flw["malaysia_alternatives"])
    print(f"  {row_id} {plant_name}: sf={sf} ma={ma}")
    updated += 1

conn.commit()
conn.close()
print(f"Done. Backfilled {updated} records.")
