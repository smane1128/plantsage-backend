"""
Developer Tools – Reset All Data

POST /dev/reset
  • Creates a timestamped backup of myplants.db in backups/
  • Truncates all user-generated tables (DELETE FROM …)
  • Does NOT drop tables or modify the schema
  • Returns backup path and row counts deleted
"""
from __future__ import annotations

import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter
from sqlalchemy import text

from database.db import engine

router = APIRouter(prefix="/dev", tags=["developer"])

# ── Tables to clear ──────────────────────────────────────────────────────────
# Order matters: child tables first to respect FK constraints.
_TABLES_TO_CLEAR = [
    "watering_history",
    "disease_scans",
    "wishlist",
    "my_garden",
    "scan_history",
]

# SQLite DB file path – resolve relative to this file's location
_DB_PATH = Path(__file__).resolve().parent.parent / "myplants.db"
_BACKUP_DIR = Path(__file__).resolve().parent.parent / "backups"


@router.post("/reset")
def reset_all_data() -> dict:
    """
    Back up the database and delete all user-generated rows.
    Schema is preserved; settings/configuration tables are untouched.
    """
    # ── 1. Create backup ─────────────────────────────────────────────────────
    _BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = _BACKUP_DIR / f"plantsage_backup_{ts}.db"

    if _DB_PATH.exists():
        shutil.copy2(_DB_PATH, backup_path)

    # ── 2. Truncate tables ───────────────────────────────────────────────────
    deleted: dict[str, int] = {}
    with engine.connect() as conn:
        conn.execute(text("PRAGMA foreign_keys = OFF"))
        for table in _TABLES_TO_CLEAR:
            try:
                result = conn.execute(
                    text(f"SELECT COUNT(*) FROM {table}")  # noqa: S608
                )
                count = result.scalar() or 0
                conn.execute(text(f"DELETE FROM {table}"))  # noqa: S608
                deleted[table] = count
            except Exception as exc:
                deleted[table] = -1  # table didn't exist yet – not an error
        conn.execute(text("PRAGMA foreign_keys = ON"))
        conn.commit()

    total = sum(v for v in deleted.values() if v >= 0)

    return {
        "success": True,
        "backup": str(backup_path),
        "deleted": deleted,
        "total_rows_deleted": total,
        "message": f"Reset completed successfully. {total} rows removed. Backup saved.",
    }
