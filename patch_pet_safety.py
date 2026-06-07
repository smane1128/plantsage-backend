"""
patch_pet_safety.py — Re-injects authoritative pet safety data for all scan_history
records where the source is 'ai' or 'unknown' AND a database entry now exists.

Run this after expanding _SAFETY / _ALIASES to update all existing records.

Usage:
    cd C:\myplants\backend
    .\venv\Scripts\Activate.ps1
    python patch_pet_safety.py
"""
from __future__ import annotations
import sys, os, json, sqlite3

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from services.pet_safety_service import lookup_pet_safety

DB_PATH = os.path.join(os.path.dirname(__file__), "myplants.db")
conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

cur.execute("SELECT id, plant_name, scientific_name, details FROM scan_history")
rows = cur.fetchall()

patched = 0
already_ok = 0
no_db_match = 0

print("=" * 72)
print(f"  {'Plant':<28}  {'Old':<10}  {'New':<10}  Action")
print("=" * 72)

for row in rows:
    rid = row["id"]
    name = row["plant_name"] or ""
    sci = row["scientific_name"] or ""
    raw = row["details"]
    if not raw:
        continue

    try:
        d = json.loads(raw)
    except Exception:
        continue

    h = d.get("health", {})
    old_status = h.get("pet_safety_status", "unknown")
    old_source = h.get("pet_safety_source", "unknown")

    # Only patch records that aren't already authoritative database entries
    if old_source == "database":
        already_ok += 1
        print(f"  {name:<28}  {old_status:<10}  {'—':<10}  OK (already database)")
        continue

    # Look up from the now-expanded service
    info = lookup_pet_safety(sci, name)

    if info["source"] != "database":
        no_db_match += 1
        print(f"  {name:<28}  {old_status:<10}  {'—':<10}  no DB match")
        continue

    # Patch the health dict
    h["pet_safety_status"] = info["status"]
    h["pet_safety_source"] = "database"
    h["pet_safe"] = info["status"] == "safe"
    h["affected_animals"] = info["affected_animals"]
    h["symptoms"] = info["symptoms"]
    h["toxicity_level"] = info["toxicity_level"]
    h["toxicity_notes"] = info["symptoms"]
    d["health"] = h

    cur.execute(
        "UPDATE scan_history SET details = ? WHERE id = ?",
        (json.dumps(d), rid)
    )
    patched += 1
    print(f"  {name:<28}  {old_status:<10}  {info['status']:<10}  PATCHED")

conn.commit()
conn.close()

print("=" * 72)
print(f"  Total: {len(rows)}  Already OK: {already_ok}  Patched: {patched}  No DB match: {no_db_match}")
print()
print("Done. Restart the backend to serve the updated records.")
