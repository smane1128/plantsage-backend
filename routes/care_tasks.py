from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, UTC, timedelta

from database.db import get_db
from models.care_task import CareTask
from models.my_garden import MyGarden
from models.scan import ScanHistory
from services.care_schedule_service import get_care_intervals

router = APIRouter(prefix="/care-tasks", tags=["care-tasks"])

_DEFAULT_INTERVALS: dict[str, int] = {
    "fertilize": 30,
    "prune":     60,
    "repot":     365,
    "pest_check": 14,
}
_VALID_TYPES = set(_DEFAULT_INTERVALS.keys())


def _days_until_due(task: CareTask) -> Optional[int]:
    if not task.last_done_at:
        return 0  # never done — due now
    last = task.last_done_at
    if last.tzinfo is not None:
        last = last.replace(tzinfo=None)
    next_due = last + timedelta(days=task.interval_days)
    delta = (next_due.date() - datetime.now(UTC).date()).days
    return delta


class CreateCareTaskRequest(BaseModel):
    plant_id:      int
    task_type:     str
    interval_days: Optional[int] = None
    notes:         Optional[str] = None


class CompleteCareTaskRequest(BaseModel):
    notes: Optional[str] = None


@router.get("")
def get_care_tasks(plant_id: Optional[int] = None, db: Session = Depends(get_db)):
    q = db.query(CareTask)
    if plant_id is not None:
        q = q.filter(CareTask.plant_id == plant_id)
    tasks = q.all()
    result = []
    for t in tasks:
        plant = db.query(MyGarden).filter(MyGarden.id == t.plant_id).first()
        result.append({
            "id":              t.id,
            "plant_id":        t.plant_id,
            "plant_name":      plant.plant_name if plant else "Unknown",
            "scientific_name": plant.scientific_name if plant else None,
            "image_path":      plant.image_path if plant else None,
            "task_type":       t.task_type,
            "interval_days":   t.interval_days,
            "last_done_at":    t.last_done_at.isoformat() if t.last_done_at else None,
            "days_until_due":  _days_until_due(t),
            "notes":           t.notes,
        })
    return result


@router.post("")
def create_care_task(request: CreateCareTaskRequest, db: Session = Depends(get_db)):
    if request.task_type not in _VALID_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"task_type must be one of {sorted(_VALID_TYPES)}"
        )
    plant = db.query(MyGarden).filter(MyGarden.id == request.plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Plant not found.")

    # Prevent duplicate task type per plant
    existing = db.query(CareTask).filter(
        CareTask.plant_id == request.plant_id,
        CareTask.task_type == request.task_type
    ).first()
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"A {request.task_type} schedule already exists for this plant."
        )

    interval = request.interval_days or _DEFAULT_INTERVALS[request.task_type]
    task = CareTask(
        plant_id=request.plant_id,
        task_type=request.task_type,
        interval_days=interval,
        last_done_at=datetime.now(UTC).replace(tzinfo=None),
        notes=request.notes,
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    label = plant.garden_name or plant.plant_name
    return {
        "id":      task.id,
        "message": f"{request.task_type.capitalize()} schedule created for '{label}'.",
    }


@router.patch("/{task_id}/complete")
def complete_care_task(
    task_id: int,
    request: CompleteCareTaskRequest = CompleteCareTaskRequest(),
    db: Session = Depends(get_db)
):
    task = db.query(CareTask).filter(CareTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Care task not found.")
    now = datetime.now(UTC).replace(tzinfo=None)
    task.last_done_at = now
    if request.notes:
        task.notes = request.notes
    db.commit()
    return {
        "message":       f"{task.task_type.capitalize()} marked as done.",
        "last_done_at":  task.last_done_at.isoformat(),
        "days_until_due": _days_until_due(task),
    }


@router.delete("/{task_id}")
def delete_care_task(task_id: int, db: Session = Depends(get_db)):
    task = db.query(CareTask).filter(CareTask.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Care task not found.")
    db.delete(task)
    db.commit()
    return {"message": "Care task schedule removed."}


@router.post("/fix-nulls")
def fix_null_last_done(db: Session = Depends(get_db)):
    """Patch any care tasks with last_done_at=NULL to today, so they aren't shown as overdue."""
    now = datetime.now(UTC).replace(tzinfo=None)
    tasks = db.query(CareTask).filter(CareTask.last_done_at == None).all()  # noqa: E711
    for t in tasks:
        t.last_done_at = now
    db.commit()
    return {"message": f"Patched {len(tasks)} tasks.", "count": len(tasks)}


@router.post("/backfill")
def backfill_care_tasks(db: Session = Depends(get_db)):
    """
    Create missing care tasks for every plant in My Garden.
    Skips plants that already have all 4 task types.
    Safe to call multiple times (idempotent).
    """
    plants = db.query(MyGarden).all()
    created_count = 0
    plant_count   = 0

    for plant in plants:
        existing_types = {
            t.task_type for t in
            db.query(CareTask).filter(CareTask.plant_id == plant.id).all()
        }
        missing = set(_DEFAULT_INTERVALS.keys()) - existing_types
        if not missing:
            continue

        plant_count += 1

        # Look up AI details from scan_history
        scan = None
        if plant.scientific_name:
            scan = db.query(ScanHistory).filter(
                ScanHistory.scientific_name.ilike(plant.scientific_name)
            ).first()
        if scan is None and plant.plant_name:
            scan = db.query(ScanHistory).filter(
                ScanHistory.plant_name.ilike(plant.plant_name)
            ).first()

        intervals = get_care_intervals(
            scan.details if scan else None,
            plant.plant_type
        )

        now = datetime.now(UTC).replace(tzinfo=None)
        for task_type, interval_days in intervals.items():
            if task_type in missing:
                db.add(CareTask(
                    plant_id=plant.id,
                    task_type=task_type,
                    interval_days=interval_days,
                    last_done_at=now,
                ))
                created_count += 1

    db.commit()
    return {
        "message":      f"Backfill complete. Created {created_count} tasks for {plant_count} plants.",
        "tasks_created": created_count,
        "plants_updated": plant_count,
    }
