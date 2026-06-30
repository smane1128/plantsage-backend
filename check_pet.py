import sqlite3, json, sys
sys.path.insert(0, '.')

conn = sqlite3.connect('myplants.db')
cur = conn.cursor()
cur.execute("SELECT id, plant_name, details FROM scan_history ORDER BY id")
for row in cur.fetchall():
    rid, name, raw = row
    if not raw:
        continue
    d = json.loads(raw)
    h = d.get('health', {})
    print(f"id={rid}  {name!r}")
    print(f"  pet_safety_status : {h.get('pet_safety_status')!r}")
    print(f"  pet_safety_source : {h.get('pet_safety_source')!r}")
    print(f"  symptoms          : {h.get('symptoms', '')[:80]!r}")
    print()
conn.close()
