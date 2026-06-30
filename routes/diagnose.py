from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session
from openai import RateLimitError, AuthenticationError
from services.openai_service import diagnose_disease
from utils.rate_limit import check_ai_rate_limit
from database.db import get_db
from models.disease_scan import DiseaseScan
from models.my_garden import MyGarden
from datetime import datetime
import json

router = APIRouter()


class DiagnoseRequest(BaseModel):
    image: str            # base64 encoded image
    plant_name: Optional[str] = None
    scientific_name: Optional[str] = None


def _safe_treatment_json(raw) -> str:
    """Ensure treatment is stored as a clean JSON string, never a Python repr."""
    if raw is None:
        return json.dumps({"immediate_actions": [], "products": [], "application": "N/A", "recovery_time": "N/A"})
    if isinstance(raw, dict):
        return json.dumps(raw)
    if isinstance(raw, str):
        t = raw.strip()
        # Already valid JSON?
        try:
            json.loads(t)
            return t
        except Exception:
            pass
        # Python repr dict — replace single quotes with double, fix booleans/None
        try:
            import ast
            parsed = ast.literal_eval(t)
            if isinstance(parsed, dict):
                return json.dumps(parsed)
        except Exception:
            pass
        # Plain text fallback
        return json.dumps({"Treatment": t})
    return json.dumps({"Treatment": str(raw)})


import ast

def _parse_treatment(raw) -> dict:
    """Robustly parse treatment stored as JSON string OR Python repr dict."""
    if raw is None or (isinstance(raw, str) and raw.strip() == ''):
        return {}
    if isinstance(raw, dict):
        return raw
    t = raw.strip()
    # 1. Valid JSON?
    try:
        return json.loads(t)
    except Exception:
        pass
    # 2. Python repr (single-quoted dict from old records)
    try:
        parsed = ast.literal_eval(t)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    # 3. Plain text — wrap in a readable key
    return {"treatment_notes": t}


def _scan_dict(r: DiseaseScan, db: Session = None) -> dict:
    treatment_parsed = _parse_treatment(r.treatment)

    # Optionally fetch linked plant health status
    plant_health_status = None
    if r.plant_id and db:
        try:
            plant = db.query(MyGarden).filter(MyGarden.id == r.plant_id).first()
            if plant:
                plant_health_status = plant.health_status
        except Exception:
            pass

    return {
        "id":                  r.id,
        "plant_id":            r.plant_id,
        "plant_name":          r.plant_name,
        "scientific_name":     r.scientific_name,
        "plant_health_status": plant_health_status,
        "disease_name":        r.disease_name,
        "severity":            r.severity,
        "description":         r.description,
        "treatment":           treatment_parsed,
        "scan_date":           r.scan_date.isoformat(),
        "updated_date":        r.updated_date.isoformat() if r.updated_date else None,
        "status":              r.status,
        "follow_up_notes":     r.follow_up_notes,
        "resolved_at":         r.resolved_at.isoformat() if r.resolved_at else None,
        "is_healthy":          bool(r.is_healthy) if r.is_healthy is not None else False,
    }


@router.post("/diagnose")
def diagnose(request: DiagnoseRequest, db: Session = Depends(get_db)):
    if not request.image:
        raise HTTPException(status_code=400, detail="Image is required")
    check_ai_rate_limit()

    try:
        result = diagnose_disease(
            request.image,
            hint_plant_name=request.plant_name,
            hint_scientific_name=request.scientific_name,
        )
    except RateLimitError:
        raise HTTPException(status_code=402, detail="OpenAI quota exceeded. Please add credits at platform.openai.com/settings/billing")
    except AuthenticationError:
        raise HTTPException(status_code=401, detail="Invalid OpenAI API key. Check your .env file.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    if "error" in result:
        raise HTTPException(status_code=422, detail=result["error"])

    # Only persist non-healthy diagnoses as active cases
    diag = result.get("diagnosis", {})
    is_healthy = (diag.get("status") or "").lower() == "healthy"
    scan_id = None
    try:
        # scientific_name: prefer hint > result
        sci_name = (request.scientific_name
                    or result.get("plant", {}).get("scientific_name"))
        scan = DiseaseScan(
            plant_name=request.plant_name or result.get("plant", {}).get("name"),
            scientific_name=sci_name,
            disease_name=diag.get("disease_name"),
            severity=diag.get("severity"),
            description=diag.get("description"),
            treatment=_safe_treatment_json(result.get("treatment")),
            status="resolved" if is_healthy else "active",
            is_healthy=is_healthy,
            updated_date=datetime.utcnow(),
        )
        db.add(scan)
        db.commit()
        scan_id = scan.id
    except Exception:
        pass

    result["_scan_id"] = scan_id
    result["_is_healthy"] = is_healthy
    return result


class LinkRequest(BaseModel):
    plant_id: int
    plant_name: Optional[str] = None


@router.post("/diagnose/{scan_id}/link")
def link_to_garden(scan_id: int, request: LinkRequest, db: Session = Depends(get_db)):
    """Link a disease scan to a My Garden plant and mark plant as sick."""
    scan = db.query(DiseaseScan).filter(DiseaseScan.id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")
    plant = db.query(MyGarden).filter(MyGarden.id == request.plant_id).first()
    if not plant:
        raise HTTPException(status_code=404, detail="Garden plant not found.")

    scan.plant_id   = request.plant_id
    scan.plant_name = request.plant_name or plant.plant_name
    scan.status     = "active"
    plant.health_status = "sick"
    db.commit()
    return {"message": f"Tracking '{scan.disease_name}' on '{plant.plant_name}'.", "scan": _scan_dict(scan, db)}


class StatusUpdateRequest(BaseModel):
    status: str          # 'active' | 'recovering' | 'resolved'
    follow_up_notes: Optional[str] = None


@router.patch("/diagnose/{scan_id}/status")
def update_status(scan_id: int, request: StatusUpdateRequest, db: Session = Depends(get_db)):
    """Update disease tracking status and keep plant health in sync."""
    allowed = {"active", "recovering", "resolved"}
    if request.status not in allowed:
        raise HTTPException(status_code=400, detail=f"status must be one of {allowed}")

    scan = db.query(DiseaseScan).filter(DiseaseScan.id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")

    scan.status = request.status
    if request.follow_up_notes is not None:
        scan.follow_up_notes = request.follow_up_notes
    scan.updated_date = datetime.utcnow()
    if request.status == "resolved":
        scan.resolved_at = datetime.utcnow()

    # Sync plant health status
    if scan.plant_id:
        plant = db.query(MyGarden).filter(MyGarden.id == scan.plant_id).first()
        if plant:
            if request.status == "resolved":
                # Only auto-set healthy if no other active/recovering diseases remain
                other_active = (db.query(DiseaseScan)
                    .filter(DiseaseScan.plant_id == scan.plant_id,
                            DiseaseScan.id != scan_id,
                            DiseaseScan.status.in_(["active", "recovering"]))
                    .first())
                if not other_active:
                    plant.health_status = "healthy"
            elif request.status == "recovering":
                plant.health_status = "recovering"
            elif request.status == "active":
                plant.health_status = "sick"
    db.commit()
    return {"message": "Status updated.", "scan": _scan_dict(scan, db)}


@router.get("/diagnose/history")
def get_disease_history(db: Session = Depends(get_db)):
    rows = (db.query(DiseaseScan)
              .order_by(DiseaseScan.scan_date.desc())
              .limit(100)
              .all())
    return [_scan_dict(r, db) for r in rows]


@router.get("/diagnose/active")
def get_active_diseases(db: Session = Depends(get_db)):
    """Return all active/recovering disease cases linked to My Garden plants."""
    rows = (db.query(DiseaseScan)
              .filter(DiseaseScan.plant_id.isnot(None),
                      DiseaseScan.status.in_(["active", "recovering"]))
              .order_by(DiseaseScan.scan_date.desc())
              .all())
    return [_scan_dict(r, db) for r in rows]


@router.delete("/diagnose/{scan_id}")
def delete_scan(scan_id: int, db: Session = Depends(get_db)):
    """Permanently delete a disease scan record."""
    scan = db.query(DiseaseScan).filter(DiseaseScan.id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")
    db.delete(scan)
    db.commit()
    return {"message": "Scan deleted."}

