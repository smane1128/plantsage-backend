"""
Plant Doctor — AI gardening consultant with full plant context.

POST /plant-doctor/chat
  plant_id : int
  message  : str
  history  : list[{role, content}]   (optional, for conversation memory)

The endpoint:
  1. Fetches ALL plant data (garden record, care tasks, watering history, disease scans, scan report)
  2. Builds a rich structured context JSON
  3. Injects into a Malaysia-specific horticulturist system prompt
  4. Returns { reply, suggestions }

Future-ready: the context schema is versioned so new fields (photos, weather, soil sensors,
fertilizer log, growth journal) can be added without breaking existing clients.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, UTC, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.db import get_db
from models.my_garden import MyGarden
from models.care_task import CareTask
from models.care_task_history import CareTaskHistory
from models.watering_history import WateringHistory
from models.disease_scan import DiseaseScan
from models.scan import ScanHistory
from services.openai_service import client as _openai_client
from utils.rate_limit import check_ai_rate_limit

log = logging.getLogger("plantsage.plant_doctor")

router = APIRouter(prefix="/plant-doctor", tags=["plant-doctor"])


# ── Request / Response schemas ────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: str       # "user" | "assistant"
    content: str


class PlantDoctorRequest(BaseModel):
    plant_id: int
    message: str
    history: Optional[list[ChatMessage]] = []

    # Future-ready optional fields (ignored for now but accepted without error)
    symptom_image_base64: Optional[str] = None   # photo of affected area
    weather_today: Optional[dict] = None          # e.g. {"temp_c": 34, "humidity_pct": 88}
    soil_moisture_pct: Optional[float] = None     # 0–100 from a sensor
    fertilizer_log: Optional[list[dict]] = None   # [{date, product, amount}]
    growth_journal: Optional[list[dict]] = None   # [{date, note, photo_url}]


class PlantDoctorResponse(BaseModel):
    reply: str
    suggestions: list[str]
    context_version: str = "1.0"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _days_ago(dt: datetime | None) -> str:
    if dt is None:
        return "never"
    dt_naive = dt.replace(tzinfo=None) if dt.tzinfo else dt
    now = datetime.now().replace(tzinfo=None)
    delta = (now - dt_naive).days
    if delta == 0:
        return "today"
    if delta == 1:
        return "yesterday"
    return f"{delta} days ago"


def _safe_json(raw) -> dict:
    if not raw:
        return {}
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _build_plant_context(plant_id: int, db: Session) -> dict:
    """Assemble every available data point for a plant into a structured dict."""

    plant: MyGarden | None = db.query(MyGarden).filter(MyGarden.id == plant_id).first()
    if plant is None:
        raise HTTPException(status_code=404, detail="Plant not found.")

    # ── Care tasks ────────────────────────────────────────────────────────────
    tasks = db.query(CareTask).filter(CareTask.plant_id == plant_id).all()
    care_tasks_ctx = {}
    for t in tasks:
        last_done = t.last_done_at
        now = datetime.now()
        days_overdue = None
        if last_done:
            last_done_naive = last_done.replace(tzinfo=None) if last_done.tzinfo else last_done
            next_due = last_done_naive.replace(tzinfo=None) + __import__('datetime').timedelta(days=t.interval_days)
            days_overdue = (now - next_due).days
        care_tasks_ctx[t.task_type] = {
            "interval_days": t.interval_days,
            "last_done": _days_ago(t.last_done_at),
            "days_overdue": max(0, days_overdue) if days_overdue and days_overdue > 0 else 0,
            "schedule_source": t.schedule_source,
        }

    # ── Watering history (last 10) ─────────────────────────────────────────
    watering_log = (
        db.query(WateringHistory)
        .filter(WateringHistory.plant_id == plant_id)
        .order_by(WateringHistory.watered_at.desc())
        .limit(10)
        .all()
    )
    watering_ctx = [_days_ago(w.watered_at) for w in watering_log]

    # ── Disease scan history (last 5) ─────────────────────────────────────
    disease_scans = (
        db.query(DiseaseScan)
        .filter(DiseaseScan.plant_id == plant_id)
        .order_by(DiseaseScan.scan_date.desc())
        .limit(5)
        .all()
    )
    disease_ctx = []
    for d in disease_scans:
        disease_ctx.append({
            "disease": d.disease_name,
            "severity": d.severity,
            "status": d.status,
            "scanned": _days_ago(d.scan_date),
            "resolved": _days_ago(d.resolved_at) if d.resolved_at else None,
            "follow_up_notes": d.follow_up_notes,
        })

    # ── Stored AI plant report ────────────────────────────────────────────
    scan_report: dict = {}
    if plant.scientific_name or plant.plant_name:
        scan = None
        if plant.scientific_name:
            scan = (
                db.query(ScanHistory)
                .filter(ScanHistory.scientific_name.ilike(plant.scientific_name))
                .first()
            )
        if scan is None and plant.plant_name:
            scan = (
                db.query(ScanHistory)
                .filter(ScanHistory.plant_name.ilike(plant.plant_name))
                .first()
            )
        if scan and scan.details:
            raw = _safe_json(scan.details)
            # Pull key care sections only (keep context concise)
            scan_report = {
                "growing": raw.get("growing", {}),
                "common_problems": raw.get("common_problems", {}),
                "seasonal_care": raw.get("seasonal_care", {}),
                "pet_safety": raw.get("pet_safety", {}),
                "space": raw.get("space", {}),
                "watering": raw.get("watering", {}),
            }

    # ── Watering interval details ─────────────────────────────────────────
    watering_interval = {
        "interval_days": plant.watering_interval_days,
        "last_watered": _days_ago(plant.last_watered_at),
    }

    # ── Assemble context ──────────────────────────────────────────────────
    return {
        "context_version": "1.0",
        "plant": {
            "id": plant.id,
            "common_name": plant.plant_name,
            "scientific_name": plant.scientific_name,
            "plant_type": plant.plant_type,
            "planting_type": plant.planting_type,       # pot | ground
            "location": plant.location,
            "garden_name": plant.garden_name,
            "health_status": plant.health_status,       # healthy | sick | recovering
            "notes": plant.notes,
            "date_added": plant.date_added.strftime("%Y-%m-%d") if plant.date_added else None,
            "purchase_date": plant.purchase_date.strftime("%Y-%m-%d") if plant.purchase_date else None,
            "suitability_score": plant.suitability_score,
        },
        "watering": watering_interval,
        "watering_log_recent": watering_ctx,
        "care_tasks": care_tasks_ctx,
        "disease_history": disease_ctx,
        "plant_report": scan_report,
        "malaysia_climate": {
            "note": "Malaysia is tropical: 26–35°C year-round, humidity 70–90%.",
            "hot_season": "March–October — hotter, drier periods",
            "rainy_season": "October–February — heavy monsoon rain, overwatering risk rises",
            "current_month": datetime.now().strftime("%B"),
        },
    }


def _build_system_prompt(context: dict) -> str:
    plant = context["plant"]
    name = plant["common_name"] or "Unknown plant"
    sci = plant["scientific_name"] or ""
    planting = plant["planting_type"] or "unknown"
    location = plant["location"] or "unspecified"
    health = plant["health_status"] or "unknown"
    notes = plant["notes"] or ""
    score = plant["suitability_score"]

    watering = context["watering"]
    last_watered = watering.get("last_watered", "unknown")
    water_interval = watering.get("interval_days")
    recent_watering = context.get("watering_log_recent", [])

    diseases = context.get("disease_history", [])
    tasks = context.get("care_tasks", {})
    report = context.get("plant_report", {})
    climate = context["malaysia_climate"]

    return f"""You are Dr. Sage — an expert Malaysian horticulturist and AI Plant Doctor.

You are consulting on a SPECIFIC plant belonging to this user. You have full access to their plant's history.
NEVER give generic internet advice. Always anchor your answer to the user's actual data below.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PATIENT PLANT RECORD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Name            : {name} ({sci})
Type            : {plant.get('plant_type', 'unknown')}
Planted in      : {planting} at {location}
Health status   : {health}
Suitability     : {score}/100 for Malaysian climate
User notes      : {notes or 'None'}

WATERING HISTORY
Last watered    : {last_watered}
Interval        : every {water_interval or '?'} days
Recent log      : {', '.join(recent_watering[:5]) if recent_watering else 'no records'}

CARE TASKS STATUS
{_format_tasks(tasks)}

DISEASE HISTORY
{_format_diseases(diseases)}

PLANT REPORT (from AI scan)
Growing reqs    : {json.dumps(report.get('growing', {}), indent=None)}
Common problems : {json.dumps(report.get('common_problems', {}), indent=None)}
Seasonal care   : {json.dumps(report.get('seasonal_care', {}), indent=None)}

MALAYSIA CLIMATE CONTEXT
Current month   : {climate['current_month']}
Hot season      : {climate['hot_season']}
Rainy season    : {climate['rainy_season']}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RESPONSE RULES:
1. Always reference the user's actual plant history in your answer.
2. Structure your response exactly as:

🩺 **Diagnosis**
[Likely cause(s) based on this plant's data]

**Confidence:** High / Medium / Low
**Why:** [Explain using their specific data — last watered, health status, recent events]

**Recommended Action:**
[Concrete step-by-step instructions]

**Monitor for:**
[Specific symptoms to watch]

**When to escalate:**
[When to run a disease scan or seek further help]

3. End with a line starting exactly: SUGGESTIONS: followed by 2–3 short action labels separated by |
   Example: SUGGESTIONS: 💧 Mark as watered|📷 Scan affected leaf|🐛 Run disease diagnosis

Available suggestion labels:
💧 Mark plant as watered
📷 Scan affected leaf
🐛 Run disease diagnosis
🌱 View care schedule
📖 Open care guide
✂️ Log pruning done
🌿 Log fertilizing done
📍 Check soil moisture
🔍 Check for pests
"""


def _format_tasks(tasks: dict) -> str:
    if not tasks:
        return "No care tasks recorded."
    lines = []
    for task_type, info in tasks.items():
        overdue = info.get("days_overdue", 0)
        status = f"⚠ {overdue}d overdue" if overdue > 0 else "OK"
        lines.append(f"  {task_type}: last done {info.get('last_done', '?')}, every {info.get('interval_days', '?')}d — {status}")
    return "\n".join(lines)


def _format_diseases(diseases: list) -> str:
    if not diseases:
        return "No disease history."
    lines = []
    for d in diseases:
        resolved = f", resolved {d['resolved']}" if d.get("resolved") else ""
        lines.append(f"  [{d.get('status', '?')}] {d.get('disease', 'Unknown')} ({d.get('severity', '?')}) — scanned {d.get('scanned', '?')}{resolved}")
    return "\n".join(lines)


def _parse_suggestions(reply: str) -> tuple[str, list[str]]:
    """Extract SUGGESTIONS line from reply, return (clean_reply, suggestions_list)."""
    lines = reply.strip().split("\n")
    suggestions = []
    clean_lines = []
    for line in lines:
        if line.strip().startswith("SUGGESTIONS:"):
            raw = line.strip()[len("SUGGESTIONS:"):].strip()
            suggestions = [s.strip() for s in raw.split("|") if s.strip()]
        else:
            clean_lines.append(line)
    return "\n".join(clean_lines).strip(), suggestions


# ── Route ─────────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=PlantDoctorResponse)
def plant_doctor_chat(request: PlantDoctorRequest, db: Session = Depends(get_db)):
    check_ai_rate_limit()

    # Build context
    context = _build_plant_context(request.plant_id, db)
    system_prompt = _build_system_prompt(context)

    # Build messages
    messages: list[dict] = [{"role": "system", "content": system_prompt}]

    for msg in (request.history or []):
        messages.append({"role": msg.role, "content": msg.content})

    messages.append({"role": "user", "content": request.message})

    # Call OpenAI
    try:
        from openai import RateLimitError, AuthenticationError
        response = _openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=700,
            temperature=0.4,   # lower = more consistent clinical tone
        )
        raw_reply = response.choices[0].message.content.strip()
    except RateLimitError:
        raise HTTPException(status_code=402, detail="OpenAI quota exceeded.")
    except AuthenticationError:
        raise HTTPException(status_code=401, detail="Invalid OpenAI API key.")
    except Exception as e:
        log.exception("Plant Doctor OpenAI error: %s", e)
        raise HTTPException(status_code=500, detail="AI service error.")

    clean_reply, suggestions = _parse_suggestions(raw_reply)

    # Default suggestions if AI forgot to include them
    if not suggestions:
        suggestions = ["💧 Mark plant as watered", "🐛 Run disease diagnosis", "🌱 View care schedule"]

    return PlantDoctorResponse(reply=clean_reply, suggestions=suggestions)


# ── Context endpoint (for debugging / future mobile use) ─────────────────────

@router.get("/context/{plant_id}")
def get_plant_context(plant_id: int, db: Session = Depends(get_db)):
    """Returns the full structured context that Plant Doctor uses — useful for debugging."""
    return _build_plant_context(plant_id, db)
