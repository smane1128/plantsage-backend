"""
One-time migration: sync ScanHistory.suitability_score DB column to the
enforced gardenability_score value stored inside the details JSON blob.

Run: python migrate_scores.py
"""
import sys, json
sys.path.insert(0, r"C:\myplants\backend")

from database.db import SessionLocal
from models.scan import ScanHistory
from services.cultivation_service import get_score_band

db = SessionLocal()
records = db.query(ScanHistory).all()
updated = 0
for r in records:
    if not r.details:
        continue
    try:
        d = json.loads(r.details)
    except Exception:
        continue
    enforced = d.get("gardenability_score")
    if enforced is None:
        continue
    enforced = int(enforced)
    if r.suitability_score != enforced:
        print(f"  [{r.id}] {r.plant_name!r}: suitability_score {r.suitability_score} -> {enforced}  band={get_score_band(enforced)['short_label']}")
        r.suitability_score = enforced
        rec_in_blob = d.get("purchase_decision", {}).get("recommendation")
        if rec_in_blob and r.recommendation != rec_in_blob:
            print(f"       rec: {r.recommendation!r} -> {rec_in_blob!r}")
            r.recommendation = rec_in_blob
        updated += 1

db.commit()
db.close()
print(f"\nDone. {updated} record(s) updated.")
