from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes.identify import router as identify_router
from routes.garden import router as garden_router
from routes.chat import router as chat_router
from routes.my_garden import router as my_garden_router
from routes.wishlist import router as wishlist_router
from routes.stats import router as stats_router
from routes.diagnose import router as diagnose_router
from routes.compare import router as compare_router
from routes.reset import router as reset_router
from routes.care_tasks import router as care_tasks_router
from database.db import engine, Base
from sqlalchemy import text
import models.garden_profile    # ensure table is registered
import models.my_garden          # ensure table is registered
import models.wishlist           # ensure table is registered
import models.watering_history   # ensure table is registered
import models.disease_scan       # ensure table is registered
import models.care_task          # ensure table is registered
import models.pet_safety_cache   # ensure table is registered
import models.care_task_history  # ensure table is registered

Base.metadata.create_all(bind=engine)

# Migrate existing DB — add new columns if they don't exist yet
with engine.connect() as _conn:
    for _sql in [
        "ALTER TABLE scan_history ADD COLUMN image_path TEXT",
        "ALTER TABLE scan_history ADD COLUMN last_viewed_at DATETIME DEFAULT NULL",
        "UPDATE scan_history SET last_viewed_at = scan_date WHERE last_viewed_at IS NULL",
        "ALTER TABLE scan_history ADD COLUMN scan_count INTEGER DEFAULT 1",
        "ALTER TABLE my_garden ADD COLUMN image_path TEXT",
        "ALTER TABLE wishlist ADD COLUMN image_path TEXT",
        # Deduplicate: keep only the latest row per scientific_name
        "DELETE FROM scan_history WHERE id NOT IN (SELECT MAX(id) FROM scan_history GROUP BY COALESCE(scientific_name, CAST(id AS TEXT)))",
        # Enforce uniqueness on non-NULL scientific_name going forward
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_scan_scientific_name ON scan_history(scientific_name) WHERE scientific_name IS NOT NULL",
        "ALTER TABLE my_garden ADD COLUMN watering_interval_days INTEGER DEFAULT NULL",
        "ALTER TABLE my_garden ADD COLUMN last_watered_at DATETIME DEFAULT NULL",
        "ALTER TABLE wishlist ADD COLUMN notes TEXT DEFAULT NULL",
        # New additions
        "ALTER TABLE my_garden ADD COLUMN health_status TEXT DEFAULT NULL",
        """CREATE TABLE IF NOT EXISTS watering_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plant_id INTEGER NOT NULL REFERENCES my_garden(id) ON DELETE CASCADE,
            watered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )""",
        """CREATE TABLE IF NOT EXISTS disease_scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plant_name TEXT,
            disease_name TEXT,
            severity TEXT,
            description TEXT,
            treatment TEXT,
            image_path TEXT,
            scan_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )""",
        # Disease tracking columns
        "ALTER TABLE disease_scans ADD COLUMN plant_id INTEGER REFERENCES my_garden(id) ON DELETE SET NULL",
        "ALTER TABLE disease_scans ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
        "ALTER TABLE disease_scans ADD COLUMN follow_up_notes TEXT",
        "ALTER TABLE disease_scans ADD COLUMN resolved_at DATETIME",
        # Extended columns
        "ALTER TABLE disease_scans ADD COLUMN scientific_name TEXT",
        "ALTER TABLE disease_scans ADD COLUMN updated_date DATETIME",
        "ALTER TABLE disease_scans ADD COLUMN is_healthy INTEGER DEFAULT 0",
        # Garden name + location per individual plant record
        "ALTER TABLE my_garden ADD COLUMN garden_name TEXT DEFAULT NULL",
        "ALTER TABLE my_garden ADD COLUMN location TEXT DEFAULT NULL",
        # Purchase date + backfill NULL date_added
        "ALTER TABLE my_garden ADD COLUMN purchase_date DATETIME DEFAULT NULL",
        "UPDATE my_garden SET date_added = CURRENT_TIMESTAMP WHERE date_added IS NULL",
        # Nursery price columns on scan_history
        "ALTER TABLE scan_history ADD COLUMN price_small TEXT DEFAULT NULL",
        "ALTER TABLE scan_history ADD COLUMN price_medium TEXT DEFAULT NULL",
        "ALTER TABLE scan_history ADD COLUMN price_large TEXT DEFAULT NULL",
        # Wishlist uniqueness (case-insensitive)
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_wishlist_plant_name ON wishlist(lower(plant_name))",
        # Pet safety columns on scan_history
        "ALTER TABLE scan_history ADD COLUMN pet_safety_status TEXT DEFAULT NULL",
        "ALTER TABLE scan_history ADD COLUMN pet_safety_source TEXT DEFAULT NULL",
        # FK indexes for query performance
        "CREATE INDEX IF NOT EXISTS idx_watering_history_plant_id ON watering_history(plant_id)",
        "CREATE INDEX IF NOT EXISTS idx_disease_scans_plant_id ON disease_scans(plant_id)",
        # Care tasks table
        """CREATE TABLE IF NOT EXISTS care_tasks (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            plant_id      INTEGER NOT NULL REFERENCES my_garden(id) ON DELETE CASCADE,
            task_type     TEXT NOT NULL,
            interval_days INTEGER NOT NULL,
            last_done_at  DATETIME,
            notes         TEXT
        )""",
        "CREATE INDEX IF NOT EXISTS idx_care_tasks_plant_id ON care_tasks(plant_id)",
        "ALTER TABLE care_tasks ADD COLUMN schedule_source VARCHAR(20) DEFAULT NULL",
        # Remove repot tasks — repotting is condition-based, not calendar-based
        "DELETE FROM care_tasks WHERE task_type = 'repot'",
        # Pet safety AI research cache
        """CREATE TABLE IF NOT EXISTS pet_safety_cache (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            scientific_name  TEXT,
            genus            TEXT,
            common_name      TEXT,
            safety_status    TEXT NOT NULL,
            confidence       INTEGER NOT NULL,
            source           TEXT NOT NULL DEFAULT 'AI_RESEARCH',
            reasoning        TEXT,
            affected_animals TEXT DEFAULT '',
            symptoms         TEXT DEFAULT '',
            toxicity_level   TEXT DEFAULT '',
            created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )""",
        "CREATE INDEX IF NOT EXISTS idx_pet_cache_sci  ON pet_safety_cache(scientific_name)",
        "CREATE INDEX IF NOT EXISTS idx_pet_cache_genus ON pet_safety_cache(genus)",
        # Planting type: pot or in-ground
        "ALTER TABLE my_garden ADD COLUMN planting_type TEXT DEFAULT NULL",
        # Care task history (completion log per task)
        """CREATE TABLE IF NOT EXISTS care_task_history (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id   INTEGER REFERENCES care_tasks(id) ON DELETE SET NULL,
            plant_id  INTEGER NOT NULL REFERENCES my_garden(id) ON DELETE CASCADE,
            task_type TEXT NOT NULL,
            done_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            notes     TEXT
        )""",
        "CREATE INDEX IF NOT EXISTS idx_care_hist_task_id  ON care_task_history(task_id)",
        "CREATE INDEX IF NOT EXISTS idx_care_hist_plant_id ON care_task_history(plant_id)",
    ]:
        try:
            _conn.execute(text(_sql))
            _conn.commit()
        except Exception as _e:
            import logging as _logging
            _logging.getLogger("plantsage.migration").debug("Migration skipped (already applied): %s", _e)

app = FastAPI(title="MyPlants API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(identify_router)
app.include_router(garden_router)
app.include_router(chat_router)
app.include_router(my_garden_router)
app.include_router(wishlist_router)
app.include_router(stats_router)
app.include_router(diagnose_router)
app.include_router(compare_router)
app.include_router(reset_router)
app.include_router(care_tasks_router)


# ── Inline routes (bypass route-file caching issue) ─────────────────────────
from fastapi import Depends as _Depends
from pydantic import BaseModel as _BaseModel
from typing import Optional as _Optional
from sqlalchemy.orm import Session as _Session
from database.db import get_db as _get_db
from models.my_garden import MyGarden as _MyGarden
from models.care_task import CareTask as _CareTask
from models.care_task_history import CareTaskHistory as _CareTaskHistory
from fastapi import HTTPException as _HTTPException
from datetime import datetime as _datetime, UTC as _UTC

class _RenamePlantReq(_BaseModel):
    garden_name: str

@app.patch("/my-garden/{plant_id}/rename")
def _rename_plant(plant_id: int, req: _RenamePlantReq, db: _Session = _Depends(_get_db)):
    p = db.query(_MyGarden).filter(_MyGarden.id == plant_id).first()
    if not p:
        raise _HTTPException(status_code=404, detail="Plant not found.")
    p.garden_name = req.garden_name.strip() or None
    db.commit()
    return {"message": "Plant renamed.", "garden_name": p.garden_name}

class _UpdateScheduleReq(_BaseModel):
    interval_days: int

@app.patch("/care-tasks/{task_id}/schedule")
def _update_care_schedule(task_id: int, req: _UpdateScheduleReq, db: _Session = _Depends(_get_db)):
    t = db.query(_CareTask).filter(_CareTask.id == task_id).first()
    if not t:
        raise _HTTPException(status_code=404, detail="Task not found.")
    t.interval_days = max(1, req.interval_days)
    db.commit()
    return {"message": "Schedule updated.", "interval_days": t.interval_days}

@app.get("/care-tasks/{task_id}/history")
def _get_care_history(task_id: int, db: _Session = _Depends(_get_db)):
    rows = (db.query(_CareTaskHistory)
              .filter(_CareTaskHistory.task_id == task_id)
              .order_by(_CareTaskHistory.done_at.desc())
              .limit(50).all())
    return [{"done_at": r.done_at.isoformat(), "notes": r.notes} for r in rows]


@app.get("/")
def root():
    import os
    key = os.getenv("OPENAI_KEY") or os.getenv("OPENAI_API_KEY", "")
    key_hint = (key[:8] + "..." + key[-4:]) if len(key) > 12 else ("SET" if key else "NOT SET")
    var_used = "OPENAI_KEY" if os.getenv("OPENAI_KEY") else "OPENAI_API_KEY"
    return {"message": "MyPlants API is running", "version": "e341c84+key2", "key_hint": key_hint, "var": var_used}


def _backfill_care_tasks():
    """Create care tasks for plants that have none (added before auto-creation was deployed)."""
    import logging
    from sqlalchemy.orm import Session
    from models.my_garden import MyGarden
    from models.care_task import CareTask
    from models.scan import ScanHistory
    from services.care_schedule_service import get_care_intervals
    from datetime import datetime, UTC

    log = logging.getLogger("plantsage.backfill")
    with Session(engine) as db:
        plants_without_tasks = (
            db.query(MyGarden)
            .filter(~MyGarden.id.in_(db.query(CareTask.plant_id).distinct()))
            .all()
        )
        if not plants_without_tasks:
            return
        log.info("Backfilling care tasks for %d plants", len(plants_without_tasks))
        now = datetime.now(UTC).replace(tzinfo=None)
        for plant in plants_without_tasks:
            scan = None
            if plant.scientific_name:
                scan = db.query(ScanHistory).filter(
                    ScanHistory.scientific_name.ilike(plant.scientific_name)
                ).first()
            if scan is None and plant.plant_name:
                scan = db.query(ScanHistory).filter(
                    ScanHistory.plant_name.ilike(plant.plant_name)
                ).first()
            details_json = scan.details if scan else None
            intervals = get_care_intervals(
                details_json,
                plant.plant_type,
                plant_name=plant.plant_name,
                scientific_name=plant.scientific_name,
            )
            for task_type, task_info in intervals.items():
                if task_info is None:
                    continue
                db.add(CareTask(
                    plant_id=plant.id,
                    task_type=task_type,
                    interval_days=task_info["interval_days"],
                    last_done_at=now,
                    schedule_source=task_info["source"],
                ))
            log.info("  → %s: %s", plant.plant_name, list(intervals.keys()))
        db.commit()


try:
    _backfill_care_tasks()
except Exception as _bf_err:
    import logging as _bl
    _bl.getLogger("plantsage.backfill").warning("Backfill skipped: %s", _bf_err)
