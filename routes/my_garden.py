import csv
import io
# v2 — rename endpoint
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from database.db import get_db
from models.my_garden import MyGarden
from models.scan import ScanHistory
from models.watering_history import WateringHistory
from models.disease_scan import DiseaseScan
from models.care_task import CareTask
from services.care_schedule_service import get_care_intervals, get_watering_interval, get_watering_recommendation
from datetime import datetime, UTC, timedelta

router = APIRouter(prefix="/my-garden", tags=["my-garden"])


class AddPlantRequest(BaseModel):
    plant_name: str
    scientific_name: Optional[str] = None
    plant_type: Optional[str] = None
    recommendation: Optional[str] = None
    suitability_score: Optional[int] = None
    notes: Optional[str] = None
    image_path: Optional[str] = None
    garden_name: Optional[str] = None
    location: Optional[str] = None
    purchase_date: Optional[str] = None   # ISO date string YYYY-MM-DD
    cultivation_category: Optional[str] = None
    planting_type: Optional[str] = None       # 'pot' | 'ground'


def _resolve_image(db: Session, stored_path: Optional[str], scientific_name: Optional[str], plant_name: Optional[str]) -> Optional[str]:
    """Return stored_path if set, else look it up from scan_history."""
    if stored_path:
        return stored_path
    scan = None
    if scientific_name:
        scan = db.query(ScanHistory).filter(ScanHistory.scientific_name.ilike(scientific_name)).first()
    if scan is None and plant_name:
        scan = db.query(ScanHistory).filter(ScanHistory.plant_name.ilike(plant_name)).first()
    return scan.image_path if scan else None


def _active_disease(db: Session, plant_id: int) -> Optional[dict]:
    """Return the most recent active/recovering disease for this plant, or None."""
    scan = (db.query(DiseaseScan)
              .filter(DiseaseScan.plant_id == plant_id,
                      DiseaseScan.status.in_(["active", "recovering"]))
              .order_by(DiseaseScan.scan_date.desc())
              .first())
    if not scan:
        return None
    return {
        "id":              scan.id,
        "disease_name":    scan.disease_name,
        "severity":        scan.severity,
        "status":          scan.status,
        "scan_date":       scan.scan_date.isoformat(),
        "treatment":       scan.treatment,
        "follow_up_notes": scan.follow_up_notes,
    }


def _days_until_water(p: MyGarden) -> Optional[int]:
    """Returns days until next watering. Negative = overdue. None = no schedule."""
    if not p.watering_interval_days:
        return None
    if not p.last_watered_at:
        return 0  # never watered, due now
    # SQLite stores datetimes as timezone-naive strings; strip tzinfo before comparing
    last = p.last_watered_at
    if last.tzinfo is not None:
        last = last.replace(tzinfo=None)
    next_water = last + timedelta(days=p.watering_interval_days)
    # Compare dates (not datetimes) so a plant watered this morning with a 1-day
    # interval shows delta=1 (due tomorrow), not delta=0 (due today).
    delta = (next_water.date() - datetime.now(UTC).date()).days
    return delta


def _care_days_until_due(t: CareTask) -> Optional[int]:
    """Days until a care task is due. Negative = overdue."""
    if not t.last_done_at:
        return 0
    last = t.last_done_at
    if last.tzinfo is not None:
        last = last.replace(tzinfo=None)
    next_due = last + timedelta(days=t.interval_days)
    return (next_due.date() - datetime.now(UTC).date()).days


def _watering_recommended(db, p: MyGarden) -> dict | None:
    """Compute watering recommendation from species DB (no AI call needed)."""
    try:
        # Try to find the scan details JSON for this plant
        details_json = None
        if p.scientific_name:
            from models.scan import ScanHistory
            scan = db.query(ScanHistory).filter(
                ScanHistory.scientific_name.ilike(p.scientific_name)
            ).first()
            if scan:
                details_json = scan.details
        return get_watering_recommendation(
            details_json,
            p.plant_type,
            plant_name=p.plant_name,
            scientific_name=p.scientific_name,
        )
    except Exception:
        return None


@router.get("")
def get_my_garden(db: Session = Depends(get_db)):
    plants = db.query(MyGarden).order_by(MyGarden.date_added.desc()).all()
    return [
        {
            "id": p.id,
            "plant_name": p.plant_name,
            "scientific_name": p.scientific_name,
            "plant_type": p.plant_type,
            "recommendation": p.recommendation,
            "suitability_score": p.suitability_score,
            "notes": p.notes,
            "image_path": _resolve_image(db, p.image_path, p.scientific_name, p.plant_name),
            "date_added": p.date_added.isoformat() if p.date_added else None,
            "watering_interval_days": p.watering_interval_days,
            "last_watered_at": p.last_watered_at.isoformat() if p.last_watered_at else None,
            "days_until_water": _days_until_water(p),
            "watering_recommended": _watering_recommended(db, p),
            "health_status": p.health_status,
            "active_disease": _active_disease(db, p.id),
            "garden_name": p.garden_name,
            "location": p.location,
            "purchase_date": p.purchase_date.isoformat() if p.purchase_date else None,
            "planting_type": p.planting_type,
            "care_tasks": [
                {
                    "id":              t.id,
                    "task_type":       t.task_type,
                    "interval_days":   t.interval_days,
                    "last_done_at":    t.last_done_at.isoformat() if t.last_done_at else None,
                    "days_until_due":  _care_days_until_due(t),
                    "schedule_source": t.schedule_source,
                }
                for t in db.query(CareTask).filter(CareTask.plant_id == p.id).order_by(CareTask.task_type).all()
            ],
        }
        for p in plants
    ]


@router.post("")
def add_to_my_garden(request: AddPlantRequest, db: Session = Depends(get_db)):
    if request.cultivation_category == 'botanical_only':
        raise HTTPException(
            status_code=422,
            detail=f"'{request.plant_name}' is a conservation/research species and cannot be added to a home garden."
        )
    # Parse optional purchase_date ISO string
    parsed_purchase_date: Optional[datetime] = None
    if request.purchase_date:
        try:
            parsed_purchase_date = datetime.fromisoformat(request.purchase_date)
        except ValueError:
            pass

    # Resolve image: use what the caller sent, or copy it from scan_history once
    # so this record is self-contained and doesn't depend on scan_history existing.
    image_path = request.image_path
    if not image_path:
        image_path = _resolve_image(db, None, request.scientific_name, request.plant_name)

    plant = MyGarden(
        plant_name=request.plant_name,
        scientific_name=request.scientific_name,
        plant_type=request.plant_type,
        recommendation=request.recommendation,
        suitability_score=request.suitability_score,
        notes=request.notes,
        image_path=image_path,
        garden_name=request.garden_name or None,
        location=request.location or None,
        purchase_date=parsed_purchase_date,
        planting_type=request.planting_type or None,
    )
    db.add(plant)
    db.commit()
    db.refresh(plant)

    # ── Auto-create care task schedules ──────────────────────────────────────
    # Look up AI details JSON from scan_history for this plant
    scan = None
    if request.scientific_name:
        scan = db.query(ScanHistory).filter(
            ScanHistory.scientific_name.ilike(request.scientific_name)
        ).first()
    if scan is None and request.plant_name:
        scan = db.query(ScanHistory).filter(
            ScanHistory.plant_name.ilike(request.plant_name)
        ).first()

    details_json = scan.details if scan else None

    # ── Auto-set watering interval if not already set ─────────────────────
    if not plant.watering_interval_days:
        rec = get_watering_recommendation(
            details_json,
            request.plant_type,
            plant_name=request.plant_name,
            scientific_name=request.scientific_name,
        )
        if request.planting_type == 'ground' and rec.get('ground_range'):
            try:
                plant.watering_interval_days = int(rec['ground_range'].split('-')[0])
            except (ValueError, IndexError):
                plant.watering_interval_days = rec['interval']
        else:
            plant.watering_interval_days = rec['interval']
    intervals = get_care_intervals(
        details_json,
        request.plant_type,
        plant_name=request.plant_name,
        scientific_name=request.scientific_name,
    )

    now = datetime.now(UTC).replace(tzinfo=None)
    for task_type, task_info in intervals.items():
        if task_info is None:
            continue  # not applicable for this plant's lifecycle
        db.add(CareTask(
            plant_id=plant.id,
            task_type=task_type,
            interval_days=task_info["interval_days"],
            last_done_at=now,
            schedule_source=task_info["source"],
        ))
    db.commit()

    label = plant.garden_name or plant.plant_name
    return {"id": plant.id, "message": f"'{label}' added to your garden!"}


@router.delete("/{plant_id}")
def remove_from_my_garden(plant_id: int, db: Session = Depends(get_db)):
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    db.delete(plant)
    db.commit()
    return {"message": f"'{plant.plant_name}' removed from your garden."}


class UpdateNotesRequest(BaseModel):
    notes: Optional[str] = None


@router.patch("/{plant_id}/notes")
def update_notes(plant_id: int, request: UpdateNotesRequest, db: Session = Depends(get_db)):
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    plant.notes = request.notes
    db.commit()
    return {"message": "Notes updated."}


class WateringScheduleRequest(BaseModel):
    interval_days: int


@router.patch("/{plant_id}/water")
def mark_watered(plant_id: int, db: Session = Depends(get_db)):
    """Mark plant as watered right now and log to watering_history."""
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    now = datetime.now(UTC).replace(tzinfo=None)  # store as naive UTC
    plant.last_watered_at = now
    db.add(WateringHistory(plant_id=plant_id, watered_at=now))
    db.commit()
    return {
        "message": f"'{plant.plant_name}' marked as watered.",
        "last_watered_at": plant.last_watered_at.isoformat(),
        "days_until_water": _days_until_water(plant),
    }


@router.patch("/{plant_id}/schedule")
def set_watering_schedule(plant_id: int, request: WateringScheduleRequest, db: Session = Depends(get_db)):
    """Set watering interval in days (0 = remove schedule)."""
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    plant.watering_interval_days = request.interval_days if request.interval_days > 0 else None
    db.commit()
    return {
        "message": f"Watering schedule set to every {request.interval_days} day(s).",
        "watering_interval_days": plant.watering_interval_days,
        "days_until_water": _days_until_water(plant),
    }


@router.get("/due")
def get_due_for_watering(db: Session = Depends(get_db)):
    """Return plants that are due or overdue for watering today."""
    plants = db.query(MyGarden).filter(MyGarden.watering_interval_days.isnot(None)).all()
    due = [p for p in plants if (_days_until_water(p) is not None and _days_until_water(p) <= 0)]
    return [{"id": p.id, "plant_name": p.plant_name, "days_until_water": _days_until_water(p)} for p in due]


class HealthStatusRequest(BaseModel):
    health_status: Optional[str] = None  # 'healthy' | 'sick' | 'recovering' | None


@router.patch("/{plant_id}/health")
def update_health(plant_id: int, request: HealthStatusRequest, db: Session = Depends(get_db)):
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    allowed = {None, 'healthy', 'sick', 'recovering'}
    if request.health_status not in allowed:
        raise HTTPException(status_code=400, detail=f"health_status must be one of {allowed}")
    plant.health_status = request.health_status
    db.commit()
    return {"message": "Health status updated.", "health_status": plant.health_status}


@router.get("/{plant_id}/watering-history")
def get_watering_history(plant_id: int, db: Session = Depends(get_db)):
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    rows = (db.query(WateringHistory)
              .filter(WateringHistory.plant_id == plant_id)
              .order_by(WateringHistory.watered_at.desc())
              .limit(50)
              .all())
    return [{"id": r.id, "watered_at": r.watered_at.isoformat()} for r in rows]


@router.get("/export/csv")
def export_garden_csv(db: Session = Depends(get_db)):    """Download all My Garden plants as a CSV file."""
    plants = db.query(MyGarden).order_by(MyGarden.date_added.desc()).all()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Plant Name", "Scientific Name", "Type",
                     "Recommendation", "Suitability Score", "Health Status",
                     "Watering Interval (days)", "Last Watered", "Date Added", "Notes"])
    for p in plants:
        writer.writerow([
            p.id, p.plant_name, p.scientific_name or '', p.plant_type or '',
            p.recommendation or '', p.suitability_score or '',
            p.health_status or '',
            p.watering_interval_days or '',
            p.last_watered_at.strftime('%Y-%m-%d %H:%M') if p.last_watered_at else '',
            p.date_added.strftime('%Y-%m-%d') if p.date_added else '',
            p.notes or '',
        ])
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=my_garden.csv"},
    )


class RenamePlantRequest(BaseModel):
    garden_name: str


@router.patch("/{plant_id}/rename")
def rename_plant(plant_id: int, request: RenamePlantRequest, db: Session = Depends(get_db)):
    """Update the custom garden name for a plant."""
    plant = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")
    plant.garden_name = request.garden_name.strip() or None
    db.commit()
    return {"message": "Plant renamed.", "garden_name": plant.garden_name}
