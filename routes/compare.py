from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database.db import get_db
from models.scan import ScanHistory
import json

router = APIRouter()


@router.get("/compare")
def compare_plants(id1: int, id2: int, db: Session = Depends(get_db)):
    plant1 = db.query(ScanHistory).filter(ScanHistory.id == id1).first()
    plant2 = db.query(ScanHistory).filter(ScanHistory.id == id2).first()
    if not plant1:
        raise HTTPException(status_code=404, detail=f"Plant {id1} not found")
    if not plant2:
        raise HTTPException(status_code=404, detail=f"Plant {id2} not found")

    def serialize(p: ScanHistory) -> dict:
        details = {}
        if p.details:
            try:
                details = json.loads(p.details)
            except Exception:
                pass
        return {
            "id": p.id,
            "plant_name": p.plant_name,
            "scientific_name": p.scientific_name,
            "recommendation": p.recommendation,
            "suitability_score": p.suitability_score,
            "image_path": p.image_path,
            "details": details,
        }

    return {
        "plant1": serialize(plant1),
        "plant2": serialize(plant2),
    }
