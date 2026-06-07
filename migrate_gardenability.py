"""One-time migration: add gardenability_score to all existing DB records."""
import sys, json
sys.path.insert(0, '.')
from services.cultivation_service import get_cultivation_category, get_gardenability_score
import sqlite3

conn = sqlite3.connect('myplants.db')
conn.row_factory = sqlite3.Row
rows = conn.execute("SELECT id, plant_name, scientific_name, details FROM scan_history").fetchall()

print(f"Migrating {len(rows)} records for gardenability_score...")
for r in rows:
    details = {}
    if r['details']:
        try:
            details = json.loads(r['details'])
        except Exception:
            pass

    ident       = details.get('identification', {})
    maintenance = details.get('maintenance', {})
    plant_name  = ident.get('plant_name') or r['plant_name'] or ''
    sci_name    = ident.get('scientific_name') or r['scientific_name'] or ''
    description = ident.get('description', '')
    difficulty  = maintenance.get('difficulty', '')

    category    = details.get('cultivation_category') or \
                  get_cultivation_category(plant_name, sci_name, description, difficulty)
    score       = get_gardenability_score(category, difficulty)

    details['gardenability_score'] = score
    details['cultivation_category'] = category

    conn.execute(
        "UPDATE scan_history SET details=? WHERE id=?",
        (json.dumps(details), r['id'])
    )
    print(f"  [{r['id']}] {plant_name!r:25s} -> {category}  gardenability={score}")

conn.commit()
conn.close()
print("Done.")
