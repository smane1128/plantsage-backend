"""One-time migration: inject cultivation_category into all existing DB records."""
import sys, json
sys.path.insert(0, '.')
from services.cultivation_service import get_cultivation_category
import sqlite3

conn = sqlite3.connect('myplants.db')
conn.row_factory = sqlite3.Row
rows = conn.execute("SELECT id, plant_name, scientific_name, details FROM scan_history").fetchall()

print(f"Migrating {len(rows)} records for cultivation_category...")
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

    cat = get_cultivation_category(plant_name, sci_name, description, difficulty)
    details['cultivation_category'] = cat

    # Apply rules for botanical_only
    if cat == 'botanical_only':
        pd = details.setdefault('purchase_decision', {})
        try:
            score = int(pd.get('suitability_score', 0))
        except (TypeError, ValueError):
            score = 0
        if score > 40:
            pd['suitability_score'] = 40
        rec = pd.get('recommendation', '')
        if rec in ('Highly Recommended', 'Recommended'):
            pd['recommendation'] = 'Consider Carefully'
        growing = details.setdefault('growing', {})
        growing['watering'] = 'Specialized cultivation required'
        suitability = details.setdefault('suitability', {})
        suitability['malaysia_suitable'] = False
        best_loc = suitability.setdefault('best_location', {})
        for key in ('balcony', 'front_yard', 'porch', 'indoor'):
            best_loc[key] = False
        flowering = details.setdefault('flowering', {})
        flowering['popular_in_region'] = []
        pd['summary'] = (
            f"{plant_name} cannot be cultivated in a home garden. "
            "This species requires institutional botanical care, a specific host plant, "
            "or protected forest conditions that cannot be replicated at home."
        )
        # Clear prices
        conn.execute(
            "UPDATE scan_history SET price_small='', price_medium='', price_large='' WHERE id=?",
            (r['id'],)
        )

    conn.execute(
        "UPDATE scan_history SET details=? WHERE id=?",
        (json.dumps(details), r['id'])
    )
    print(f"  [{r['id']}] {plant_name!r:25s} sci={sci_name!r:30s}  -> {cat}")

conn.commit()
conn.close()
print("Done.")
