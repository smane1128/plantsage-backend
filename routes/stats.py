from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session
from urllib.parse import quote
from database.db import get_db, DATABASE_URL
from models.my_garden import MyGarden
from models.wishlist import Wishlist
from models.scan import ScanHistory
from models.disease_scan import DiseaseScan
from datetime import datetime, timedelta
from typing import Optional
import requests as req
import os

router = APIRouter()

# In-session cache: plant_name → (bytes, media_type) | None
_image_cache: dict = {}
_IMAGE_CACHE_MAX = 200


def _cache_set(key: str, value) -> None:
    """Write to the image cache, evicting the oldest entry when the cap is hit."""
    if len(_image_cache) >= _IMAGE_CACHE_MAX:
        oldest = next(iter(_image_cache))
        del _image_cache[oldest]
    _image_cache[key] = value

_SUPPORTED_TYPES = ("image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp")
# Wikipedia API accepts any descriptive UA; the image CDN (upload.wikimedia.org) rejects
# placeholder email addresses — use a browser-style UA for binary downloads.
_HEADERS = {
    'User-Agent': 'PlantSageApp/1.0 (https://github.com/plantsage; plant identification app)'
}
_IMG_HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36'
    )
}


def _download_image(url: str) -> tuple[bytes, str] | None | str:
    """Download a URL and return (bytes, media_type), None (not found), or 'rate_limited'."""
    try:
        r = req.get(url, headers=_IMG_HEADERS, timeout=10)
        if r.status_code == 429:
            import logging as _log
            _log.getLogger("plantsage.image").warning("_download_image: rate limited (429) url=%s", url[:80])
            return "rate_limited"
        ct = r.headers.get("content-type", "image/jpeg").split(";")[0].strip()
        if r.status_code == 200 and any(ct.startswith(s) for s in _SUPPORTED_TYPES):
            return r.content, ct
        import logging as _log
        _log.getLogger("plantsage.image").warning(
            "_download_image: %s  status=%s  ct=%s  bytes=%d",
            url[:80], r.status_code, ct, len(r.content)
        )
    except Exception as e:
        import logging as _log
        _log.getLogger("plantsage.image").warning("_download_image exception: %s  url=%s", e, url[:80])
    return None


def _wiki_thumb_url(title: str) -> str | None:
    """Return Wikipedia pageimages thumbnail URL for title, or None."""
    try:
        url = (
            f"https://en.wikipedia.org/w/api.php?action=query"
            f"&titles={quote(title)}&prop=pageimages&format=json"
            f"&pithumbsize=500&redirects=1&origin=*"
        )
        pages = req.get(url, headers=_HEADERS, timeout=6).json().get("query", {}).get("pages", {})
        for page in pages.values():
            th = page.get("thumbnail")
            if th:
                return th["source"]
    except Exception:
        pass
    return None


def _inaturalist_photo_url(name: str) -> str | None:
    """Return iNaturalist species photo URL, or None."""
    try:
        url = (
            f"https://api.inaturalist.org/v1/taxa"
            f"?q={quote(name)}&per_page=3&order_by=observations_count&order=desc"
        )
        results = req.get(url, headers=_HEADERS, timeout=8).json().get("results", [])
        for taxon in results:
            photo = taxon.get("default_photo") or {}
            img = photo.get("medium_url") or photo.get("square_url")
            if img:
                return img
    except Exception:
        pass
    return None


import re as _re

def _normalize_image_query(name: str) -> str:
    """Normalize a plant name for Wikipedia/iNaturalist image lookup.

    - Strips generic ' sp.' / ' spp.' / ' var.' / ' subsp.' suffixes so
      'Lilium sp.' → 'Lilium', 'Rosa sp.' → 'Rosa', etc.
    - Strips trailing parenthetical labels like ' (Global)', ' (Purple)',
      ' (Dancing Lady)', ' (Coneflower)' which confuse Wikipedia search.
    """
    # Remove trailing parenthetical
    name = _re.sub(r'\s*\([^)]*\)\s*$', '', name).strip()
    # Remove generic rank suffixes
    name = _re.sub(r'\s+(sp\.|spp\.|var\.|subsp\.|f\.)\s*$', '', name, flags=_re.IGNORECASE).strip()
    return name


@router.get("/plant-image")
def get_plant_image(name: str):
    """Proxy plant image from Wikipedia or iNaturalist so Flutter can load it via localhost."""
    import logging as _log
    _logger = _log.getLogger("plantsage.image")

    # Serve from in-session cache
    if name in _image_cache:
        cached = _image_cache[name]
        if cached is None:
            raise HTTPException(status_code=404, detail="No image found")
        return Response(content=cached[0], media_type=cached[1])

    image_url: str | None = None
    _logger.info("plant-image request: %r", name)

    # Normalize the name for external lookups (strip " sp.", parentheticals)
    query = _normalize_image_query(name)
    if query != name:
        _logger.info("plant-image normalized: %r → %r", name, query)

    # Source 1: Wikipedia exact title match
    image_url = _wiki_thumb_url(query)
    _logger.info("wiki exact url: %s", image_url)

    # Source 2: Wikipedia search fallback (top 3 results)
    if not image_url:
        try:
            search_resp = req.get(
                f"https://en.wikipedia.org/w/api.php?action=query&list=search"
                f"&srsearch={quote(query)}+plant&srlimit=3&format=json&origin=*",
                headers=_HEADERS, timeout=6
            ).json().get("query", {}).get("search", [])
            for hit in search_resp:
                image_url = _wiki_thumb_url(hit["title"])
                if image_url:
                    _logger.info("wiki search hit %r -> %s", hit["title"], image_url)
                    break
        except Exception as e:
            _logger.warning("wiki search failed: %s", e)

    # Source 3: iNaturalist (scientific species database with high-quality photos)
    if not image_url:
        image_url = _inaturalist_photo_url(query)
        _logger.info("inat url: %s", image_url)

    # Download and validate the image bytes
    if image_url:
        result = _download_image(image_url)
        if result == "rate_limited":
            # Do NOT cache — allow retry on next request
            _logger.warning("plant-image: rate limited for %r — not caching, will retry", name)
            raise HTTPException(status_code=503, detail="Image source temporarily unavailable, please retry")
        if result:
            _cache_set(name, result)
            _logger.info("plant-image OK: %r  ct=%s  %d bytes", name, result[1], len(result[0]))
            return Response(content=result[0], media_type=result[1])

    _logger.warning("plant-image: no image found for %r (url tried: %s)", name, image_url)
    _cache_set(name, None)
    raise HTTPException(status_code=404, detail="No image found")


def _days_until_water_stat(p: MyGarden) -> Optional[int]:
    """Returns days until next watering. Negative = overdue. None = no schedule."""
    if not p.watering_interval_days:
        return None
    if not p.last_watered_at:
        return 0
    last = p.last_watered_at
    if last.tzinfo is not None:
        last = last.replace(tzinfo=None)
    next_water = last + timedelta(days=p.watering_interval_days)
    return (next_water.date() - datetime.utcnow().date()).days


@router.get("/stats")
def get_stats(db: Session = Depends(get_db)):
    garden_count = db.query(MyGarden).count()
    wishlist_count = db.query(Wishlist).count()
    scan_count = db.query(ScanHistory).count()

    top_pick = db.query(MyGarden).filter(
        MyGarden.recommendation.ilike("highly recommended")
    ).count()
    good = db.query(MyGarden).filter(
        MyGarden.recommendation.ilike("recommended")
    ).count()
    careful = db.query(MyGarden).filter(
        MyGarden.recommendation.ilike("consider carefully")
    ).count()
    risky = db.query(MyGarden).filter(
        MyGarden.recommendation.ilike("not recommended")
    ).count()

    scores = db.query(MyGarden.suitability_score).filter(
        MyGarden.suitability_score.isnot(None)
    ).all()
    avg_score = round(sum(s[0] for s in scores) / len(scores)) if scores else 0

    # ── Health status counts ──────────────────────────────────────────────────
    healthy_count    = db.query(MyGarden).filter(MyGarden.health_status == 'healthy').count()
    recovering_count = db.query(MyGarden).filter(MyGarden.health_status == 'recovering').count()
    sick_count       = db.query(MyGarden).filter(MyGarden.health_status == 'sick').count()

    # ── Watering summary ─────────────────────────────────────────────────────
    watering_plants = db.query(MyGarden).filter(MyGarden.watering_interval_days.isnot(None)).all()
    needs_water   = sum(1 for p in watering_plants if (_days_until_water_stat(p) or 1) <= 0)
    upcoming_water = sum(1 for p in watering_plants
                         if 1 <= (_days_until_water_stat(p) or -99) <= 7)

    # ── Garden Health Score ───────────────────────────────────────────────────
    total_with_health = healthy_count + recovering_count + sick_count
    if total_with_health == 0:
        garden_health_score = 100
    else:
        raw_pct = (healthy_count * 100 + recovering_count * 70 + sick_count * 20) / (total_with_health * 100) * 100
        overdue_penalty = min(25, needs_water * 5)
        garden_health_score = max(0, round(raw_pct - overdue_penalty))

    # ── Today's Tasks ─────────────────────────────────────────────────────────
    tasks_today: list = []
    task_ids: set = set()
    for p in watering_plants:
        d = _days_until_water_stat(p)
        if d is None:
            continue
        if d <= 0:
            task_type = 'overdue' if d < 0 else 'water_due'
            tasks_today.append({
                'id': p.id, 'plant_name': p.plant_name,
                'image_path': p.image_path, 'type': task_type,
                'days_overdue': abs(d) if d < 0 else 0,
            })
            task_ids.add(p.id)
    for p in db.query(MyGarden).filter(MyGarden.health_status == 'sick').all():
        if p.id not in task_ids:
            tasks_today.append({'id': p.id, 'plant_name': p.plant_name,
                                'image_path': p.image_path, 'type': 'sick', 'days_overdue': 0})
            task_ids.add(p.id)
    for p in db.query(MyGarden).filter(MyGarden.health_status == 'recovering').all():
        if p.id not in task_ids:
            tasks_today.append({'id': p.id, 'plant_name': p.plant_name,
                                'image_path': p.image_path, 'type': 'recovery', 'days_overdue': 0})
            task_ids.add(p.id)

    # ── Top Plant ─────────────────────────────────────────────────────────────
    top_plant_obj = db.query(MyGarden).filter(
        MyGarden.suitability_score.isnot(None)
    ).order_by(MyGarden.suitability_score.desc()).first()
    top_plant = None
    if top_plant_obj:
        top_plant = {
            'id': top_plant_obj.id, 'plant_name': top_plant_obj.plant_name,
            'scientific_name': top_plant_obj.scientific_name,
            'score': top_plant_obj.suitability_score,
            'recommendation': top_plant_obj.recommendation,
            'image_path': top_plant_obj.image_path,
        }

    # ── Recent activity ───────────────────────────────────────────────────────
    last_scan_obj    = db.query(ScanHistory).order_by(ScanHistory.scan_date.desc()).first()
    last_disease_obj = db.query(DiseaseScan).order_by(DiseaseScan.scan_date.desc()).first()

    last_scan = None
    if last_scan_obj:
        last_scan = {
            "name": last_scan_obj.plant_name,
            "date": last_scan_obj.scan_date.isoformat() if last_scan_obj.scan_date else None,
            "image_path": last_scan_obj.image_path,
        }

    last_disease = None
    if last_disease_obj:
        last_disease = {
            "plant_name": last_disease_obj.plant_name or "Unknown Plant",
            "disease_name": last_disease_obj.disease_name,
            "date": last_disease_obj.scan_date.isoformat() if last_disease_obj.scan_date else None,
            "status": last_disease_obj.status,
        }

    return {
        "garden_count": garden_count,
        "wishlist_count": wishlist_count,
        "scan_count": scan_count,
        "avg_score": avg_score,
        "top_pick": top_pick,
        "good": good,
        "careful": careful,
        "risky": risky,
        # Health
        "healthy_count": healthy_count,
        "recovering_count": recovering_count,
        "sick_count": sick_count,
        # Watering
        "needs_water": needs_water,
        "upcoming_water": upcoming_water,
        # Garden health
        "garden_health_score": garden_health_score,
        # Today's tasks
        "tasks_today": tasks_today,
        # Top plant
        "top_plant": top_plant,
        # Recent activity
        "last_scan": last_scan,
        "last_disease": last_disease,
    }


@router.get("/stats/about")
def get_about(db: Session = Depends(get_db)):
    """Returns data for the Settings / About screen."""
    garden_count   = db.query(MyGarden).count()
    scan_count     = db.query(ScanHistory).count()
    wishlist_count = db.query(Wishlist).count()

    # Disease resolved count (for milestone)
    disease_resolved_count = db.query(DiseaseScan).filter(
        DiseaseScan.status == "resolved"
    ).count()

    # Days since first ever activity (oldest my_garden or scan record)
    days_gardening = 0
    earliest_dt = None
    first_garden = db.query(MyGarden.date_added).order_by(MyGarden.date_added.asc()).first()
    first_scan   = db.query(ScanHistory.scan_date).order_by(ScanHistory.scan_date.asc()).first()

    def _dt(val):
        """Coerce to a naive datetime, or return None."""
        if val is None:
            return None
        if isinstance(val, datetime):
            return val.replace(tzinfo=None) if val.tzinfo else val
        try:
            return datetime.fromisoformat(str(val))
        except Exception:
            return None

    if first_garden:
        earliest_dt = _dt(first_garden[0])
    if first_scan:
        sd = _dt(first_scan[0])
        if sd is not None and (earliest_dt is None or sd < earliest_dt):
            earliest_dt = sd
    if earliest_dt:
        days_gardening = max(0, (datetime.utcnow() - earliest_dt).days)

    # Resolve the SQLite file path regardless of CWD
    raw_url = DATABASE_URL  # e.g. "sqlite:///./myplants.db"
    db_rel = raw_url.replace("sqlite:///", "").lstrip("./").lstrip("/")
    # stats.py lives at  backend/routes/stats.py  → go up two levels to reach backend/
    backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    db_abs = os.path.join(backend_dir, db_rel)
    db_size_mb: float = 0.0
    if os.path.exists(db_abs):
        db_size_mb = round(os.path.getsize(db_abs) / (1024 * 1024), 2)

    return {
        "db_size_mb":              db_size_mb,
        "garden_count":            garden_count,
        "scan_count":              scan_count,
        "wishlist_count":          wishlist_count,
        "disease_resolved_count":  disease_resolved_count,
        "days_gardening":          days_gardening,
    }
