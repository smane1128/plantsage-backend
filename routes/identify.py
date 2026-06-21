from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from openai import RateLimitError, AuthenticationError
from datetime import datetime, timezone
from database.db import get_db
from models.scan import ScanHistory
from models.garden_profile import GardenProfile
from services.openai_service import identify_plant, identify_plant_multi, quick_get_scientific_name, ai_research_pet_safety
from services.pricing_service import generate_nursery_price
from services.recommendation_service import get_similar_plants, get_similar_flowers, get_malaysia_alternatives
from services.pet_safety_service import lookup_pet_safety
from services.cultivation_service import get_cultivation_category, get_gardenability_score, is_special_plant, get_botanical_info, get_score_band, get_location_override
from services.plant_rules import get_display_mode
from services.care_schedule_service import get_watering_recommendation
from utils.rate_limit import check_ai_rate_limit
import json

router = APIRouter()

# Strings the AI may literally return when it has nothing specific to say.
# We strip these so the Flutter UI can show "No information available" instead.
_PLACEHOLDER_STRINGS: set[str] = {
    "Benefit 1", "Benefit 2", "Benefit 3", "Benefit 4", "Benefit 5",
    "Challenge 1", "Challenge 2", "Challenge 3", "Challenge 4",
    "Advantage 1", "Advantage 2", "Advantage 3",
}

# Generic one-liners that appear verbatim for dozens of different plants.
# These are NOT stripped outright—only flagged in debug—so real data is never lost.
_SUSPECT_GENERIC: set[str] = {
    "Vibrant colors", "Fast-growing", "Drought-tolerant",
    "Requires regular pruning", "Toxic to pets",
    "Low maintenance", "Easy to grow", "Attractive foliage",
}


def _strip_placeholders(result: dict) -> None:
    """Remove literal placeholder strings from advantages/challenges."""
    pd = result.get("purchase_decision", {})
    if "advantages" in pd:
        cleaned = [a for a in pd["advantages"] if a.strip() and a not in _PLACEHOLDER_STRINGS]
        pd["advantages"] = cleaned
    if "challenges" in pd:
        cleaned = [c for c in pd["challenges"] if c.strip() and c not in _PLACEHOLDER_STRINGS]
        pd["challenges"] = cleaned

    plant_name = result.get("identification", {}).get("plant_name", "Unknown")
    adv = pd.get("advantages", [])
    chl = pd.get("challenges", [])
    suspect_adv = [a for a in adv if a in _SUSPECT_GENERIC]
    suspect_chl = [c for c in chl if c in _SUSPECT_GENERIC]
    if suspect_adv:
        print(f"[identify] WARN: {plant_name} advantages contain suspect-generic items: {suspect_adv}")
    if suspect_chl:
        print(f"[identify] WARN: {plant_name} challenges contain suspect-generic items: {suspect_chl}")

def _inject_prices(scan_record, result: dict | None) -> None:
    """Generate nursery prices from the AI result and store on the scan record.

    If result is None (lazy-generation for cached records without stored details),
    we derive what we can from the record's own fields.
    Botanical-only plants get empty prices (not commercially available).
    """
    # Plants with gardenability_score <= 20 are not commercially available (Not Recommended band)
    if result and result.get("gardenability_score", 100) <= 20:
        scan_record.price_small  = ""
        scan_record.price_medium = ""
        scan_record.price_large  = ""
        return

    if result:
        ident = result.get("identification", {})
        space = result.get("space", {})
        purchase = result.get("purchase_decision", {})
        prices = generate_nursery_price(
            plant_name=ident.get("plant_name", scan_record.plant_name or ""),
            scientific_name=ident.get("scientific_name", scan_record.scientific_name or ""),
            plant_type=ident.get("plant_type", ""),
            recommendation=purchase.get("recommendation", scan_record.recommendation or ""),
            mature_height=space.get("mature_height", ""),
        )
    else:
        prices = generate_nursery_price(
            plant_name=scan_record.plant_name or "",
            scientific_name=scan_record.scientific_name or "",
            recommendation=scan_record.recommendation or "",
        )
    scan_record.price_small = prices["small"]
    scan_record.price_medium = prices["medium"]
    scan_record.price_large = prices["large"]


def _inject_pet_safety(scan_record, result: dict, db=None) -> None:
    """Hybrid pet safety engine — 3-level architecture.

    Level 1 — VERIFIED_DATABASE (confidence=100):
        Check pet_safety_service.py first. Result always wins over AI.
    Level 2 — AI_RESEARCH:
        If no DB entry, check pet_safety_cache table, then call GPT-4o.
        Saves successful results to cache for future lookups.
    Level 3 — UNKNOWN:
        If AI confidence < 70, force status=unknown.
        Never classify a low-confidence plant as Safe.
    """
    ident = result.get("identification", {})
    sci_name    = ident.get("scientific_name") or scan_record.scientific_name or ""
    common_name = ident.get("plant_name")      or scan_record.plant_name      or ""

    print(f"[pet_safety] inject → plant='{common_name}' sci='{sci_name}'")
    health = result.setdefault("health", {})

    # ── LEVEL 1: Verified database ────────────────────────────────────────────
    db_info = lookup_pet_safety(sci_name, common_name)
    if db_info["source"] == "VERIFIED_DATABASE":
        print(f"[pet_safety] L1 VERIFIED_DATABASE → status={db_info['status']}")
        health["pet_safety_status"]     = db_info["status"]
        health["pet_safety_source"]     = "VERIFIED_DATABASE"
        health["pet_safety_confidence"] = 100
        health["pet_safe"]              = db_info["status"] == "safe"
        health["affected_animals"]      = db_info["affected_animals"]
        health["symptoms"]              = db_info["symptoms"]
        health["toxicity_level"]        = db_info["toxicity_level"]
        health["toxicity_notes"]        = db_info["symptoms"]
        scan_record.pet_safety_status = health["pet_safety_status"]
        scan_record.pet_safety_source = health["pet_safety_source"]
        return

    # ── LEVEL 2: AI Research (cache-first) ────────────────────────────────────
    if db is not None:
        from models.pet_safety_cache import PetSafetyCache
        genus = sci_name.split()[0].lower() if sci_name else ""

        # 2a — Cache lookup (exact scientific name, then genus)
        cached = None
        if sci_name:
            cached = db.query(PetSafetyCache).filter(
                PetSafetyCache.scientific_name == sci_name.lower()
            ).first()
        if cached is None and genus:
            cached = db.query(PetSafetyCache).filter(
                PetSafetyCache.genus == genus
            ).first()

        if cached is not None:
            print(f"[pet_safety] L2 CACHE HIT → status={cached.safety_status} conf={cached.confidence}")
            health["pet_safety_status"]     = cached.safety_status
            health["pet_safety_source"]     = "AI_RESEARCH"
            health["pet_safety_confidence"] = cached.confidence
            health["pet_safe"]              = cached.safety_status == "safe"
            health["affected_animals"]      = cached.affected_animals or ""
            health["symptoms"]              = cached.symptoms or ""
            health["toxicity_level"]        = cached.toxicity_level or ""
            health["toxicity_notes"]        = cached.symptoms or ""
            scan_record.pet_safety_status = health["pet_safety_status"]
            scan_record.pet_safety_source = health["pet_safety_source"]
            return

        # 2b — AI research call
        ai = ai_research_pet_safety(sci_name, common_name)
        print(f"[pet_safety] L2 AI_RESEARCH → status={ai['safety_status']} conf={ai['confidence']}")

        if ai["confidence"] >= 70:
            # Save to cache so subsequent lookups skip the AI call
            entry = PetSafetyCache(
                scientific_name=sci_name.lower() or None,
                genus=genus or None,
                common_name=common_name.lower() or None,
                safety_status=ai["safety_status"],
                confidence=ai["confidence"],
                source="AI_RESEARCH",
                reasoning=ai.get("reasoning", ""),
                affected_animals=ai.get("affected_animals", ""),
                symptoms=ai.get("symptoms", ""),
                toxicity_level=ai.get("toxicity_level", ""),
            )
            db.add(entry)
            try:
                db.commit()
            except Exception as _ce:
                db.rollback()
                print(f"[pet_safety] cache save failed (non-fatal): {_ce}")

            health["pet_safety_status"]     = ai["safety_status"]
            health["pet_safety_source"]     = "AI_RESEARCH"
            health["pet_safety_confidence"] = ai["confidence"]
            health["pet_safe"]              = ai["safety_status"] == "safe"
            health["affected_animals"]      = ai.get("affected_animals", "")
            health["symptoms"]              = ai.get("symptoms", "")
            health["toxicity_level"]        = ai.get("toxicity_level", "")
            health["toxicity_notes"]        = ai.get("symptoms", "")
            scan_record.pet_safety_status = health["pet_safety_status"]
            scan_record.pet_safety_source = health["pet_safety_source"]
            return

        print(f"[pet_safety] L2 AI low-confidence ({ai['confidence']}) → falling to L3")

    # ── LEVEL 3: Unknown — insufficient data ──────────────────────────────────
    print(f"[pet_safety] L3 UNKNOWN for '{common_name}'")
    health["pet_safety_status"]     = "unknown"
    health["pet_safety_source"]     = "unknown"
    health["pet_safety_confidence"] = 0
    health["pet_safe"]              = False
    health["affected_animals"]      = ""
    health["symptoms"]              = ""
    health["toxicity_level"]        = ""
    health["toxicity_notes"]        = ""
    scan_record.pet_safety_status = "unknown"
    scan_record.pet_safety_source = "unknown"


_RECOMMENDATION_RANK = {
    "Highly Recommended": 3,
    "Recommended": 2,
    "Consider Carefully": 1,
    "Not Recommended": 0,
}

# Keywords that indicate a cold-dormancy / temperate-only requirement.
# Any of these found in description, seasonal_care, or challenges → apply Malaysia penalty.
_COLD_DORMANCY_KEYWORDS: tuple[str, ...] = (
    "cold dormancy",
    "winter dormancy",
    "requires cold",
    "needs cold",
    "cold period",
    "chilling requirement",
    "chilling hours",
    "vernalization",
    "frost requirement",
    "temperate climate",
    "cool winter",
    "cold stratification",
    "below 10",
    "below 5°c",
    "subzero",
    # Additional keywords for spring bulbs, corms, and cool-season plants (e.g. Crocus)
    "cool temperature",
    "requires cool",
    "needs cool",
    "cool climate",
    "cool growing",
    "cool season",
    "cool period",
    "cool conditions",
    "cool dry",
    "cool rest",
    "spring bulb",
    "spring flowering bulb",
    "bulb dormancy",
    "corm dormancy",
    "corm requires",
    "dry dormancy",
    "not suitable for tropical",
    "unsuitable for tropical",
    "cannot survive tropical",
    "does not thrive in tropical",
)

# Score caps keyed by recommendation label.
# These align with the canonical score bands in cultivation_service._SCORE_BANDS:
#   Not Recommended    ≤ 20  (band 10-20)
#   Consider Carefully ≤ 40  (band 21-40 Challenging)
#   Recommended        ≤ 80  (band 61-80)
#   Highly Recommended ≤ 100 (band 81-100)
_SCORE_CAP_BY_RECOMMENDATION = {
    "Not Recommended":    20,
    "Consider Carefully": 40,
    "Recommended":        80,
    "Highly Recommended": 100,
}
_MALAYSIA_UNSUITABLE_CAP = 20   # Rule 1: malaysia_suitable==False → score ≤ 20 (Not Recommended)
_COLD_DORMANCY_PENALTY   = 15   # Safely within Not Recommended band (10-20)


def _enforce_score_consistency(result: dict, plant_name: str) -> None:
    """
    Post-processing step that makes gardenability_score, suitability_score,
    and recommendation label always logically consistent.

    Hard validation rules (applied in order):
      Rule 1: Cold-dormancy plants → gardenability ≤ 15 (Not Recommended), malaysia_suitable=False
      Rule 2: malaysia_suitable == False → gardenability ≤ 20 (Not Recommended band)
      Rule 3: gardenability_score capped by recommendation label
      Rule 4: Recommendation label forced DOWN to match gardenability_score:
               0-20   → Not Recommended
               21-40  → Consider Carefully  (Challenging band)
               41-80  → Recommended
               81-100 → Highly Recommended
      Rule 5: suitability_score synced to gardenability_score
    """
    pd          = result.setdefault("purchase_decision", {})
    suitability = result.get("suitability", {})
    maintenance = result.get("maintenance", {})
    ident       = result.get("identification", {})

    # ── Gather text for keyword scan ─────────────────────────────────────────
    description   = ident.get("description", "").lower()
    seasonal_care = maintenance.get("seasonal_care", "").lower()
    challenges    = " ".join(pd.get("challenges", [])).lower()
    scan_text     = f"{description} {seasonal_care} {challenges}"

    malaysia_suitable = suitability.get("malaysia_suitable", True)
    rec               = pd.get("recommendation", "")
    current_score     = result.get("gardenability_score", 75)

    # ── 1. Cold-dormancy / temperate-only penalty ─────────────────────────────
    has_cold_dormancy = any(kw in scan_text for kw in _COLD_DORMANCY_KEYWORDS)
    if has_cold_dormancy:
        if current_score > _COLD_DORMANCY_PENALTY:
            print(f"[consistency] {plant_name!r}: cold-dormancy detected → score {current_score} → {_COLD_DORMANCY_PENALTY}")
            current_score = _COLD_DORMANCY_PENALTY
        if _RECOMMENDATION_RANK.get(rec, 0) > 0:
            print(f"[consistency] {plant_name!r}: cold-dormancy → recommendation {rec!r} → 'Not Recommended'")
            rec = "Not Recommended"
        # Disable Malaysia suitability
        suitability["malaysia_suitable"] = False
        malaysia_suitable = False

    # ── 2. Malaysia unsuitable cap ────────────────────────────────────────────
    if not malaysia_suitable and current_score > _MALAYSIA_UNSUITABLE_CAP:
        print(f"[consistency] {plant_name!r}: malaysia_suitable=False → score {current_score} → {_MALAYSIA_UNSUITABLE_CAP}")
        current_score = _MALAYSIA_UNSUITABLE_CAP

    # ── 3. Cap gardenability from recommendation label ────────────────────────
    rec_cap = _SCORE_CAP_BY_RECOMMENDATION.get(rec, 100)
    if current_score > rec_cap:
        print(f"[consistency] {plant_name!r}: rec={rec!r} → score {current_score} → {rec_cap}")
        current_score = rec_cap

    # ── 4. Force recommendation label DOWN to match gardenability_score ───────
    # Thresholds align with canonical score bands in cultivation_service._SCORE_BANDS:
    #   0-9   → Botanical Only (treat as Not Recommended for rec label)
    #  10-20  → Not Recommended
    #  21-40  → Consider Carefully  (Challenging band)
    #  41-80  → Recommended         (Moderate + Recommended bands)
    #  81-100 → Highly Recommended
    if current_score <= 20:
        forced_rec = "Not Recommended"
    elif current_score <= 40:
        forced_rec = "Consider Carefully"
    elif current_score <= 80:
        forced_rec = "Recommended"
    else:
        forced_rec = "Highly Recommended"

    if _RECOMMENDATION_RANK.get(rec, -1) != _RECOMMENDATION_RANK.get(forced_rec, -1):
        # Only allow downgrading — never upgrade what the AI says
        if _RECOMMENDATION_RANK.get(forced_rec, 0) < _RECOMMENDATION_RANK.get(rec, 0):
            print(f"[consistency] {plant_name!r}: score={current_score} → downgrade rec {rec!r} → {forced_rec!r}")
            rec = forced_rec
        # If forced_rec would upgrade, cap the score down to match the AI rec instead
        elif _RECOMMENDATION_RANK.get(forced_rec, 0) > _RECOMMENDATION_RANK.get(rec, 0):
            new_cap = _SCORE_CAP_BY_RECOMMENDATION.get(rec, 100)
            if current_score > new_cap:
                print(f"[consistency] {plant_name!r}: ai rec={rec!r} → score capped {current_score} → {new_cap}")
                current_score = new_cap

    # ── 5. Sync suitability_score to gardenability_score ─────────────────────
    pd["recommendation"]   = rec
    pd["suitability_score"] = current_score
    result["gardenability_score"] = current_score
    # ── 6. Inject canonical score_band (single source of truth for UI labels) ────
    result["score_band"] = get_score_band(current_score)
    print(f"[consistency] {plant_name!r}: final score={current_score}  band={result['score_band']['label']!r}  rec={rec!r}  malaysia={malaysia_suitable}")


def _inject_cultivation_category(result: dict, from_cache: bool = False) -> str:
    """Determine cultivation category and apply business rules to result.

    Returns the category string ('common_garden' | 'specialty_garden' |
    'advanced_collector' | 'botanical_only').
    Mutates result in-place.
    """
    ident       = result.get("identification", {})
    maintenance = result.get("maintenance", {})

    plant_name  = ident.get("plant_name", "")
    sci_name    = ident.get("scientific_name", "")
    description = ident.get("description", "")
    difficulty  = maintenance.get("difficulty", "")

    # ── Debug: pre-injection state ───────────────────────────────────────────
    print(f"[inject] ──────────────────────────────────────────────────────")
    print(f"[inject] Plant: {plant_name!r}  (sci: {sci_name!r})")
    print(f"[inject] Loaded From Cache: {from_cache}")

    category = get_cultivation_category(plant_name, sci_name, description, difficulty)
    result["cultivation_category"] = category

    score_before = get_gardenability_score(category, difficulty)
    result["gardenability_score"] = score_before

    special = is_special_plant(plant_name, sci_name, category)
    result["special_plant"] = special

    # Inject accurate educational facts for known special plants
    if special:
        bio = get_botanical_info(plant_name, sci_name)
        if bio:
            result["botanical_info"] = bio
            print(f"[inject] botanical_info injected for {plant_name!r}")
        else:
            print(f"[inject] no hardcoded botanical_info for {plant_name!r}")

    print(f"[inject] Is Special Plant: {special}")
    print(f"[inject] Score Before Validation: {score_before}")

    if score_before < 40:
        pd = result.setdefault("purchase_decision", {})

        # Cap suitability score at 40
        current_score = pd.get("suitability_score", 0)
        try:
            current_score = int(current_score)
        except (TypeError, ValueError):
            current_score = 0
        if current_score > 40:
            pd["suitability_score"] = 40
            print(f"[inject] capped AI suitability_score {current_score} → 40")

        # Restrict recommendation to max 'Consider Carefully'
        rec = pd.get("recommendation", "")
        if _RECOMMENDATION_RANK.get(rec, 0) > _RECOMMENDATION_RANK["Consider Carefully"]:
            pd["recommendation"] = "Consider Carefully"
            print(f"[inject] downgraded recommendation {rec!r} → 'Consider Carefully'")

        # Override watering schedule
        growing = result.setdefault("growing", {})
        growing["watering"] = "Specialized cultivation required"

        # Disable all garden location recommendations
        suitability = result.setdefault("suitability", {})
        suitability["malaysia_suitable"] = False
        best_loc = suitability.setdefault("best_location", {})
        for key in list(best_loc.keys()):
            best_loc[key] = False
        # Explicit list in case best_location is empty (new scan)
        for key in ("balcony", "front_yard", "porch", "indoor", "garden_bed",
                    "garden_beds", "open_garden", "rooftop"):
            best_loc[key] = False

        # Exclude from 'Most Popular In Your Region'
        flowering = result.setdefault("flowering", {})
        flowering["popular_in_region"] = []

        # Override summary to explain why
        pd["summary"] = (
            f"{plant_name} cannot be cultivated in a home garden. "
            "This species requires institutional botanical care, a specific host plant, "
            "or protected forest conditions that cannot be replicated at home."
        )

    score_after = result["gardenability_score"]
    print(f"[inject] Score After Validation: {score_after}")

    # ── Location overrides (aquatic + container-garden) ────────────────────────
    # Applied AFTER special-plant rules.  Covers:
    #   • Aquatic plants (Lotus, Water Lily, Papyrus, etc.)
    #   • Container-friendly ornamentals (Rose, Hibiscus, Bougainvillea, etc.)
    if not special:
        loc_override = get_location_override(plant_name, sci_name)
        if loc_override:
            suitability = result.setdefault("suitability", {})
            best_loc    = suitability.setdefault("best_location", {})
            conditional: dict[str, str] = {}
            for loc, val in loc_override.items():
                if isinstance(val, bool):
                    best_loc[loc] = val
                elif isinstance(val, str) and val.startswith("conditional:"):
                    best_loc[loc] = False   # backward-compat bool kept False; UI reads conditional dict
                    conditional[loc] = val[len("conditional:"):]
            if conditional:
                best_loc["conditional"] = conditional
            print(f"[inject] Location override applied: conditional={list(conditional.keys())}")
        else:
            # ── Fallback auto-correction ──────────────────────────────────────────
            # If the AI says pot_or_ground=Pot/Both but marked balcony=False,
            # auto-upgrade to True for non-tree, non-aquatic plants.
            # This catches plants not yet in the explicit override dict.
            growing  = result.get("growing", {})
            pot_mode = (growing.get("pot_or_ground") or "").lower()
            suitability = result.setdefault("suitability", {})
            best_loc    = suitability.setdefault("best_location", {})
            ptype        = (result.get("identification", {}).get("plant_type") or "").lower()
            _BALCONY_EXCLUDED = {"tree", "aquatic", "bamboo"}
            _INVASIVE_NAMES   = {"bamboo", "wedelia", "water hyacinth", "sphagneticola"}

            if (
                ("pot" in pot_mode or "both" in pot_mode)
                and not best_loc.get("balcony", False)
                and not best_loc.get("conditional", {})
                and all(excl not in ptype for excl in _BALCONY_EXCLUDED)
                and all(inv not in plant_name.lower() for inv in _INVASIVE_NAMES)
            ):
                best_loc["balcony"] = True
                print(f"[inject] Auto-upgraded balcony=True for {plant_name!r} (pot_or_ground={pot_mode!r})")

    # ── Final enforcement: score ↔ recommendation ↔ malaysia_suitable ────────
    _enforce_score_consistency(result, plant_name)

    print(f"[inject] ──────────────────────────────────────────────────────")

    return category


class AdditionalImage(BaseModel):
    image: str        # base64 encoded image
    type: str = "leaf"  # leaf | stem | flower


class ImageRequest(BaseModel):
    image: str = ""       # base64 encoded primary image (single-photo, backward compat)
    image_path: str = ""   # local file path saved by Flutter
    force_rescan: bool = False  # bypass cache and call AI fresh
    additional_images: list[AdditionalImage] = []  # extra typed photos for multi-photo scan


@router.post("/identify")
def identify(request: ImageRequest, db: Session = Depends(get_db)):
    if not request.image and not request.additional_images:
        raise HTTPException(status_code=400, detail="Image is required")
    check_ai_rate_limit()

    # Build unified image list for multi-photo flow
    all_images: list[dict] = []
    if request.additional_images:
        all_images = [{"image_base64": img.image, "type": img.type} for img in request.additional_images]
        if request.image and not any(img.image == request.image for img in request.additional_images):
            all_images.insert(0, {"image_base64": request.image, "type": "whole_plant"})
    elif request.image:
        all_images = [{"image_base64": request.image, "type": "whole_plant"}]

    is_multi = len(all_images) > 1
    # Primary image used for quick pre-check and cache storage
    primary_image = request.image or (all_images[0]["image_base64"] if all_images else "")

    now = datetime.now(timezone.utc)

    # ── Step 1: Cheap pre-check — get scientific name only (skips full AI if cached) ──
    # Use flower image for pre-check if available (most diagnostic)
    flower_images = [img for img in all_images if img["type"] in ("flower", "fruit")]
    precheck_image = flower_images[0]["image_base64"] if flower_images else primary_image
    sci_name_quick = quick_get_scientific_name(precheck_image)
    if sci_name_quick and not request.force_rescan:
        cached = db.query(ScanHistory).filter(
            ScanHistory.scientific_name.ilike(sci_name_quick)
        ).first()
        if cached and cached.details:
            # Plant known — reuse stored report, no full AI call needed
            cached.scan_count = (cached.scan_count or 1) + 1
            cached.last_viewed_at = now
            if request.image_path:
                cached.image_path = request.image_path
            # Lazy-generate prices if not yet stored
            if not cached.price_small:
                _inject_prices(cached, None)
            db.commit()
            result = json.loads(cached.details)
            # Strip any placeholder strings that may have been stored from old scans
            _strip_placeholders(result)
            # Re-apply cultivation rules (fast, deterministic)
            _inject_cultivation_category(result, from_cache=True)

            # Debug: log what's in DB before injection
            old_status = result.get("health", {}).get("pet_safety_status", "<not set>")
            old_source = result.get("health", {}).get("pet_safety_source", "<not set>")
            print(f"[refresh] BEFORE inject: plant={cached.plant_name!r} sci={cached.scientific_name!r}")
            print(f"[refresh] BEFORE pet_safety_status={old_status!r} pet_safety_source={old_source!r}")

            # Always re-resolve pet safety (cheap DB lookup, corrects old cached data)
            _inject_pet_safety(cached, result, db)

            new_status = result.get("health", {}).get("pet_safety_status", "<not set>")
            new_source = result.get("health", {}).get("pet_safety_source", "<not set>")
            print(f"[refresh] AFTER  pet_safety_status={new_status!r} pet_safety_source={new_source!r}")

            # ── FIX: write the patched result back to DB so legacy stale JSON is cured ──
            # Generate similar plants BEFORE saving so they are persisted
            fresh_similar = get_similar_plants(result)
            fresh_flowers = get_similar_flowers(result)
            fresh_alternatives = get_malaysia_alternatives(result)
            flw = result.setdefault("flowering", {})
            flw["similar_plants"] = fresh_similar
            flw["similar_flowers"] = fresh_flowers
            flw["malaysia_alternatives"] = fresh_alternatives
            print(f"[similar_plants] cache-hit path: flowers={len(fresh_flowers)} alts={len(fresh_alternatives)} for {cached.plant_name!r}")
            # ── SYNC DB columns to post-enforcement values (single source of truth) ──
            enforced_score = result.get("gardenability_score", cached.suitability_score)
            enforced_rec   = result.get("purchase_decision", {}).get("recommendation", cached.recommendation)
            if cached.suitability_score != enforced_score or cached.recommendation != enforced_rec:
                print(f"[sync] cache-hit: col suitability_score {cached.suitability_score} → {enforced_score}")
                cached.suitability_score = enforced_score
                cached.recommendation    = enforced_rec
            cached.details = json.dumps(result)
            db.commit()  # persist updated details + pet_safety columns + synced score

            result["_meta"] = {
                "already_exists": True,
                "scan_count": cached.scan_count,
                "cached": True,
            }
            if result.get("gardenability_score", 100) <= 20:
                result["nursery_price"] = {
                    "small": "", "medium": "", "large": "",
                    "unavailable_message": "Not commercially available",
                    "confidence": "N/A",
                }
            else:
                result["nursery_price"] = {
                    "small":  cached.price_small,
                    "medium": cached.price_medium,
                    "large":  cached.price_large,
                    "confidence": "Estimated",
                }
            result["display_mode"] = get_display_mode(result)
            result["watering_recommended"] = get_watering_recommendation(
                json.dumps(result),
                result.get("identification", {}).get("plant_type"),
                plant_name=result.get("identification", {}).get("plant_name"),
                scientific_name=result.get("identification", {}).get("scientific_name"),
            )
            return result

    # ── Step 2: New plant — load garden profile and generate full AI report ──
    profile = db.query(GardenProfile).filter(GardenProfile.id == 1).first()
    garden_profile = None
    if profile and any([profile.location, profile.garden_size, profile.sunlight]):
        garden_profile = {
            "location": profile.location,
            "garden_size": profile.garden_size,
            "sunlight": profile.sunlight,
            "soil_type": profile.soil_type,
            "water_availability": profile.water_availability,
        }

    try:
        if is_multi:
            result = identify_plant_multi(all_images, garden_profile=garden_profile)
        else:
            result = identify_plant(primary_image, garden_profile=garden_profile)
    except RateLimitError:
        raise HTTPException(status_code=402, detail="OpenAI quota exceeded. Please add credits at platform.openai.com/settings/billing")
    except AuthenticationError:
        raise HTTPException(status_code=401, detail="Invalid OpenAI API key. Check your .env file.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    if "error" in result:
        raise HTTPException(status_code=422, detail=result["error"])

    # ── Step 3: Save new plant record ──
    identification = result.get("identification", {})
    purchase = result.get("purchase_decision", {})
    sci_name = identification.get("scientific_name")
    common_name = identification.get("plant_name", "Unknown")

    # Fallback: check again by common name (for plants with no scientific name)
    existing = None
    if sci_name:
        existing = db.query(ScanHistory).filter(ScanHistory.scientific_name.ilike(sci_name)).first()
    if existing is None and common_name:
        existing = db.query(ScanHistory).filter(
            ScanHistory.plant_name == common_name,
            ScanHistory.scientific_name.is_(None),
        ).first()

    if existing:
        existing.plant_name = common_name
        existing.scientific_name = sci_name or existing.scientific_name
        # NOTE: do NOT set recommendation/suitability_score from raw AI values here.
        # They are set only after enforcement runs (_inject_cultivation_category → _enforce_score_consistency)
        # in the SYNC block below, so the DB column is always the post-enforcement value.
        if request.image_path:
            existing.image_path = request.image_path
        existing.last_viewed_at = now
        existing.scan_count = (existing.scan_count or 1) + 1
        # Strip placeholder/generic content from fresh AI result
        _strip_placeholders(result)
        # Apply cultivation category rules before pricing
        _inject_cultivation_category(result, from_cache=False)
        # Always regenerate prices on a full AI rescan (force_rescan or new scan)
        _inject_prices(existing, result)

        # Debug: log pet_safety before and after
        print(f"[refresh] FULL AI RESCAN: plant={common_name!r} sci={sci_name!r}")
        print(f"[refresh] AI returned pet_safe={result.get('health', {}).get('pet_safe')!r}")
        _inject_pet_safety(existing, result, db)
        print(f"[refresh] AFTER inject: pet_safety_status={result.get('health', {}).get('pet_safety_status')!r} source={result.get('health', {}).get('pet_safety_source')!r}")

        # Generate similar plants BEFORE saving details so the full list is persisted
        fresh_similar = get_similar_plants(result)
        fresh_flowers = get_similar_flowers(result)
        fresh_alternatives = get_malaysia_alternatives(result)
        flw = result.setdefault("flowering", {})
        flw["similar_plants"] = fresh_similar
        flw["similar_flowers"] = fresh_flowers
        flw["malaysia_alternatives"] = fresh_alternatives
        print(f"[similar_plants] existing-record path: flowers={len(fresh_flowers)} alts={len(fresh_alternatives)} for {common_name!r}")
        # ── SYNC DB columns to post-enforcement values (single source of truth) ──
        enforced_score = result.get("gardenability_score", existing.suitability_score)
        enforced_rec   = result.get("purchase_decision", {}).get("recommendation", existing.recommendation)
        if existing.suitability_score != enforced_score or existing.recommendation != enforced_rec:
            print(f"[sync] existing: col suitability_score {existing.suitability_score} → {enforced_score}")
            existing.suitability_score = enforced_score
            existing.recommendation    = enforced_rec
        existing.details = json.dumps(result)
        db.commit()
        result["_meta"] = {
            "already_exists": True,
            "scan_count": existing.scan_count,
            "cached": False,
        }
    else:
        scan = ScanHistory(
            plant_name=common_name,
            scientific_name=sci_name,
            recommendation=purchase.get("recommendation"),
            suitability_score=purchase.get("suitability_score"),
            details=None,
            image_path=request.image_path or None,
            last_viewed_at=now,
            scan_count=1,
        )
        db.add(scan)
        # Strip placeholder/generic content from fresh AI result
        _strip_placeholders(result)
        # Apply cultivation category rules before pricing
        _inject_cultivation_category(result, from_cache=False)
        _inject_prices(scan, result)
        _inject_pet_safety(scan, result, db)

        # Generate similar plants BEFORE saving details so the full list is persisted
        fresh_similar = get_similar_plants(result)
        fresh_flowers = get_similar_flowers(result)
        fresh_alternatives = get_malaysia_alternatives(result)
        flw = result.setdefault("flowering", {})
        flw["similar_plants"] = fresh_similar
        flw["similar_flowers"] = fresh_flowers
        flw["malaysia_alternatives"] = fresh_alternatives
        print(f"[similar_plants] new-record path: flowers={len(fresh_flowers)} alts={len(fresh_alternatives)} for {common_name!r}")
        # ── SYNC DB columns to post-enforcement values (single source of truth) ──
        enforced_score = result.get("gardenability_score", scan.suitability_score)
        enforced_rec   = result.get("purchase_decision", {}).get("recommendation", scan.recommendation)
        print(f"[sync] new: col suitability_score {scan.suitability_score} → {enforced_score}")
        scan.suitability_score = enforced_score
        scan.recommendation    = enforced_rec
        scan.details = json.dumps(result)
        db.commit()
        result["_meta"] = {
            "already_exists": False,
            "scan_count": 1,
            "cached": False,
        }

    # Always attach nursery_price to the response from the stored values
    record = existing if existing else scan
    if result.get("gardenability_score", 100) <= 20:
        result["nursery_price"] = {
            "small": "", "medium": "", "large": "",
            "unavailable_message": "Not commercially available",
            "confidence": "N/A",
        }
    else:
        result["nursery_price"] = {
            "small":  record.price_small,
            "medium": record.price_medium,
            "large":  record.price_large,
            "confidence": "Estimated",
        }
    result["display_mode"] = get_display_mode(result)
    # Attach watering recommendation
    result["watering_recommended"] = get_watering_recommendation(
        json.dumps(result),
        result.get("identification", {}).get("plant_type"),
        plant_name=result.get("identification", {}).get("plant_name"),
        scientific_name=result.get("identification", {}).get("scientific_name"),
    )
    # Attach evidence metadata for multi-photo scans
    if is_multi:
        result["_evidence"] = {
            "photos": [img["type"] for img in all_images],
            "count": len(all_images),
        }
    return result


@router.get("/history")
def get_history(db: Session = Depends(get_db)):
    scans = db.query(ScanHistory).order_by(ScanHistory.last_viewed_at.desc()).limit(20).all()
    result = []
    for s in scans:
        # gardenability_score from the JSON details is the single enforced source of truth.
        # The DB column (suitability_score) can lag on old records; always prefer the JSON value.
        gs: int = s.suitability_score or 0
        if s.details:
            try:
                d = json.loads(s.details)
                gs = int(d.get("gardenability_score") or gs)
            except Exception:
                pass
        result.append({
            "id": s.id,
            "plant_name": s.plant_name,
            "scientific_name": s.scientific_name,
            "recommendation": s.recommendation,
            # Always expose the JSON-derived gardenability_score as suitability_score so
            # every consumer (dashboard badge, sort, stats) uses the same enforced value.
            "suitability_score": gs,
            "gardenability_score": gs,
            "score_band": get_score_band(gs),
            "scan_date": s.scan_date,
            "last_viewed_at": s.last_viewed_at,
            "scan_count": s.scan_count or 1,
            "details": s.details,
            "image_path": s.image_path,
        })
    return result


@router.delete("/history/{scan_id}")
def delete_history_item(scan_id: int, db: Session = Depends(get_db)):
    scan = db.query(ScanHistory).filter(ScanHistory.id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")
    db.delete(scan)
    db.commit()
    return {"message": "Deleted"}


@router.delete("/history")
def clear_all_history(db: Session = Depends(get_db)):
    db.query(ScanHistory).delete()
    db.commit()
    return {"message": "All history cleared"}


@router.get("/debug/scan")
def debug_scan(name: str = "", db: Session = Depends(get_db)):
    """Return raw DB fields for a plant, for diagnosing pet_safety and refresh issues.

    Usage: GET /debug/scan?name=Rose
    Returns the stored DB columns AND the pet_safety fields parsed from the details JSON.
    """
    query = db.query(ScanHistory)
    if name:
        query = query.filter(ScanHistory.plant_name.ilike(f"%{name}%"))
    records = query.order_by(ScanHistory.last_viewed_at.desc()).limit(10).all()

    results = []
    for s in records:
        details = {}
        if s.details:
            try:
                details = json.loads(s.details)
            except Exception:
                pass

        health_json = details.get("health", {})
        pd_json = details.get("purchase_decision", {})

        results.append({
            # ── DB columns ────────────────────────────────────────────────────
            "db": {
                "id": s.id,
                "plant_name": s.plant_name,
                "scientific_name": s.scientific_name,
                "recommendation": s.recommendation,
                "suitability_score": s.suitability_score,
                "scan_count": s.scan_count,
                "scan_date": str(s.scan_date),
                "last_viewed_at": str(s.last_viewed_at),
                "price_small": s.price_small,
                "price_medium": s.price_medium,
                "price_large": s.price_large,
                "pet_safety_status": s.pet_safety_status,   # DB column (fast path)
                "pet_safety_source": s.pet_safety_source,   # DB column (fast path)
            },
            # ── Fields inside the stored details JSON blob ────────────────────
            "details_json": {
                "health.pet_safe": health_json.get("pet_safe"),
                "health.pet_safety_status": health_json.get("pet_safety_status"),
                "health.pet_safety_source": health_json.get("pet_safety_source"),
                "health.affected_animals": health_json.get("affected_animals"),
                "health.symptoms": health_json.get("symptoms"),
                "health.toxicity_notes": health_json.get("toxicity_notes"),
                "health.toxicity_level": health_json.get("toxicity_level"),
                "purchase_decision.advantages": pd_json.get("advantages", []),
                "purchase_decision.challenges": pd_json.get("challenges", []),
                "purchase_decision.summary": pd_json.get("summary", ""),
                "identification.scientific_name": details.get("identification", {}).get("scientific_name"),
            },
        })

    return {"count": len(results), "records": results}
