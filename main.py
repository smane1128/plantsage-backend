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
from database.db import engine, Base
from sqlalchemy import text
import models.garden_profile    # ensure table is registered
import models.my_garden          # ensure table is registered
import models.wishlist           # ensure table is registered
import models.watering_history   # ensure table is registered
import models.disease_scan       # ensure table is registered

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


@app.get("/")
def root():
    return {"message": "MyPlants API is running"}
