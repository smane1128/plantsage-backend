from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from database.db import get_db
from models.wishlist import Wishlist
from models.my_garden import MyGarden
from models.scan import ScanHistory
from models.care_task import CareTask
from services.care_schedule_service import get_care_intervals, get_watering_recommendation
from datetime import datetime, UTC

router = APIRouter(prefix="/wishlist", tags=["wishlist"])


class AddWishlistRequest(BaseModel):
    plant_name: str
    scientific_name: Optional[str] = None
    plant_type: Optional[str] = None
    recommendation: Optional[str] = None
    suitability_score: Optional[int] = None
    image_path: Optional[str] = None
    cultivation_category: Optional[str] = None


def _resolve_image(db: Session, stored_path, scientific_name, plant_name):
    if stored_path:
        return stored_path
    scan = None
    if scientific_name:
        scan = db.query(ScanHistory).filter(ScanHistory.scientific_name.ilike(scientific_name)).first()
    if scan is None and plant_name:
        scan = db.query(ScanHistory).filter(ScanHistory.plant_name.ilike(plant_name)).first()
    return scan.image_path if scan else None


@router.get("")
def get_wishlist(db: Session = Depends(get_db)):
    plants = db.query(Wishlist).order_by(Wishlist.date_added.desc()).all()
    return [
        {
            "id": p.id,
            "plant_name": p.plant_name,
            "scientific_name": p.scientific_name,
            "plant_type": p.plant_type,
            "recommendation": p.recommendation,
            "suitability_score": p.suitability_score,
            "image_path": _resolve_image(db, p.image_path, p.scientific_name, p.plant_name),
            "notes": p.notes,
            "date_added": p.date_added.isoformat() if p.date_added else None,
        }
        for p in plants
    ]


@router.post("")
def add_to_wishlist(request: AddWishlistRequest, db: Session = Depends(get_db)):
    if request.cultivation_category == 'botanical_only':
        raise HTTPException(
            status_code=422,
            detail=f"'{request.plant_name}' is a conservation/research species and cannot be added to a wishlist."
        )
    existing = db.query(Wishlist).filter(Wishlist.plant_name.ilike(request.plant_name)).first()
    if existing:
        raise HTTPException(status_code=409, detail=f"'{request.plant_name}' is already in your wishlist.")

    # Resolve image: use what the caller sent, or copy it from scan_history once
    # so this record is self-contained and doesn't depend on scan_history existing.
    image_path = request.image_path
    if not image_path:
        image_path = _resolve_image(db, None, request.scientific_name, request.plant_name)

    plant = Wishlist(
        plant_name=request.plant_name,
        scientific_name=request.scientific_name,
        plant_type=request.plant_type,
        recommendation=request.recommendation,
        suitability_score=request.suitability_score,
        image_path=image_path,
    )
    db.add(plant)
    db.commit()
    db.refresh(plant)
    return {"id": plant.id, "message": f"'{plant.plant_name}' added to your wishlist!"}


@router.delete("/{plant_id}")
def remove_from_wishlist(plant_id: int, db: Session = Depends(get_db)):
    plant = db.query(Wishlist).filter(Wishlist.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    db.delete(plant)
    db.commit()
    return {"message": f"'{plant.plant_name}' removed from wishlist."}


class UpdateWishlistNotesRequest(BaseModel):
    notes: Optional[str] = None


@router.patch("/{plant_id}/notes")
def update_wishlist_notes(plant_id: int, request: UpdateWishlistNotesRequest, db: Session = Depends(get_db)):
    plant = db.query(Wishlist).filter(Wishlist.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    plant.notes = request.notes
    db.commit()
    return {"message": "Notes updated."}


@router.post("/{plant_id}/move-to-garden")
def move_to_garden(plant_id: int, db: Session = Depends(get_db)):
    plant = db.query(Wishlist).filter(Wishlist.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found in wishlist.")

    # Check not already in garden
    existing = db.query(MyGarden).filter(MyGarden.plant_name.ilike(plant.plant_name)).first()
    if existing:
        db.delete(plant)
        db.commit()
        raise HTTPException(status_code=409, detail=f"'{plant.plant_name}' is already in your garden.")

    garden_plant = MyGarden(
        plant_name=plant.plant_name,
        scientific_name=plant.scientific_name,
        plant_type=plant.plant_type,
        recommendation=plant.recommendation,
        suitability_score=plant.suitability_score,
        image_path=plant.image_path,
    )
    db.add(garden_plant)
    db.delete(plant)
    db.commit()
    db.refresh(garden_plant)

    # ── Auto-create care task schedules (same as add_to_garden) ──────────────
    scan = None
    if garden_plant.scientific_name:
        scan = db.query(ScanHistory).filter(
            ScanHistory.scientific_name.ilike(garden_plant.scientific_name)
        ).first()
    if scan is None and garden_plant.plant_name:
        scan = db.query(ScanHistory).filter(
            ScanHistory.plant_name.ilike(garden_plant.plant_name)
        ).first()

    details_json = scan.details if scan else None

    # Set watering interval
    rec = get_watering_recommendation(
        details_json, garden_plant.plant_type,
        plant_name=garden_plant.plant_name,
        scientific_name=garden_plant.scientific_name,
    )
    garden_plant.watering_interval_days = rec['interval']

    # Create care tasks
    intervals = get_care_intervals(
        details_json, garden_plant.plant_type,
        plant_name=garden_plant.plant_name,
        scientific_name=garden_plant.scientific_name,
    )
    now = datetime.now(UTC).replace(tzinfo=None)
    for task_type, task_info in intervals.items():
        if task_info is None:
            continue
        db.add(CareTask(
            plant_id=garden_plant.id,
            task_type=task_type,
            interval_days=task_info["interval_days"],
            last_done_at=now,
            schedule_source=task_info["source"],
        ))
    db.commit()

    return {"message": f"'{garden_plant.plant_name}' moved to your garden!"}
