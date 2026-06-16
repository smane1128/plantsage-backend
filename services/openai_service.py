import base64
import json
from openai import OpenAI
from dotenv import load_dotenv
import os

def _detect_mime(image_bytes: bytes) -> str:
    if image_bytes[:8] == b'\x89PNG\r\n\x1a\n':
        return 'image/png'
    if image_bytes[:3] == b'\xff\xd8\xff':
        return 'image/jpeg'
    if image_bytes[:4] == b'RIFF' and image_bytes[8:12] == b'WEBP':
        return 'image/webp'
    if image_bytes[:6] in (b'GIF87a', b'GIF89a'):
        return 'image/gif'
    return 'image/jpeg'

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

PLANT_PROMPT = """
You are analyzing a plant for a Malaysian gardener. Malaysia is a tropical country with:
- Year-round warmth (26-35°C) and high humidity (70-90%)
- Two main seasons: Hot/Dry Season (approx. March-October) and Rainy/Monsoon Season (approx. October-February)
- NO spring, summer, autumn, or winter — use Hot Season / Rainy Season instead

Analyze this plant image carefully and return comprehensive information.

Return ONLY a valid JSON object with this exact structure:
{
  "identification": {
    "plant_name": "Common name",
    "scientific_name": "Scientific/Latin name",
    "plant_family": "Plant family (e.g. Rosaceae)",
    "plant_type": "tree / shrub / flower / vegetable / herb / succulent / vine / grass / other",
    "origin": "Country or region of origin",
    "confidence_level": 85,
    "description": "2-3 sentence description of the plant",
    "image_features": ["leaves only", "no flowers", "no fruit", "no bark visible"],
    "low_confidence_reason": "Only leaves/stems visible — many tropical trees share similar foliage"
  },
  "possible_matches": [
    {"plant_name": "Most Likely Species", "scientific_name": "Genus species", "confidence": 70, "distinguishing_note": "Why this might be correct"},
    {"plant_name": "Alternative Species", "scientific_name": "Genus species", "confidence": 55, "distinguishing_note": "Similar foliage but different fruit shape"},
    {"plant_name": "Third Candidate", "scientific_name": "Genus species", "confidence": 40, "distinguishing_note": "Cannot rule out without flowers"}
  ],
  "suitability": {
    "climate": "Suitable climate type (e.g. Tropical, Temperate, Arid)",
    "malaysia_suitable": true,
    "temperature_range": "e.g. 26-35°C",
    "sunlight": "Full Sun / Partial Shade / Full Shade",
    "humidity": "Low / Medium / High",
    "wind_tolerance": "Low / Moderate / High",
    "best_location": {
      "balcony": false,
      "front_yard": true,
      "porch": true,
      "indoor": false
    }
  },
  "growing": {
    "soil_type": "e.g. Well-draining loam, Sandy, Clay",
    "soil_ph": "e.g. 6.0-7.0",
    "watering": "e.g. Daily / Weekly / Fortnightly",
    "fertilizer": "e.g. Monthly balanced NPK",
    "mulching": "Recommended / Optional / Not needed",
    "pot_or_ground": "Pot / Ground / Both",
    "drainage": "e.g. Good drainage required"
  },
  "space": {
    "mature_height": "e.g. 1-2m",
    "mature_width": "e.g. 0.5-1m",
    "growth_rate": "Slow / Moderate / Fast",
    "root_spread": "e.g. 0.5m radius",
    "spacing": "e.g. 60cm apart"
  },
  "maintenance": {
    "pruning": "e.g. Annual light pruning",
    "pest_susceptibility": "Low / Medium / High (and common pests)",
    "disease_susceptibility": "Low / Medium / High (and common diseases)",
    "difficulty": "Easy / Medium / Hard",
    "seasonal_care": "e.g. Water twice daily in Hot Season. Ensure good drainage in Rainy Season."
  },
  "flowering": {
    "flower_color": "Primary flower color or N/A",
    "flower_colors": ["Color1", "Color2"],
    "flowering_season": "e.g. Year-round / Hot Season (Mar-Oct) / Rainy Season (Oct-Feb) or specific months",
    "fruiting_season": "e.g. Autumn or N/A",
    "harvest_info": "e.g. Harvest when fully ripe or N/A",
    "popular_varieties": [
      {"name": "Variety Name", "difficulty": "Easy", "note": "Most Popular"}
    ],
    "popular_in_region": ["Top Variety", "Second", "Third"],
    "price_small": "RM15 - RM25",
    "price_medium": "RM30 - RM50",
    "price_large": "RM60+",
    "similar_plants": [{"name": "Common Name", "scientific_name": "Genus species"}, ...]
  },
  "purchase_decision": {
    "advantages": ["Blooms continuously in Malaysia's year-round heat", "Drought-tolerant once established — low water bills"],
    "challenges": ["Thorny stems require thick gloves when pruning", "Susceptible to aphids during prolonged dry spells"],
    "suitability_score": 75,
    "recommendation": "Highly Recommended / Recommended / Consider Carefully / Not Recommended",
    "summary": "1-2 sentence purchase summary"
  },
  "health": {
    "health_status": "Healthy / Unhealthy",
    "disease": "None or name of disease/condition detected",
    "pet_safe": true,
    "toxicity_notes": "Safe for all pets OR description of toxicity (e.g. Toxic to cats and dogs: causes vomiting)"
  }
}

Rules:
- confidence_level and suitability_score must be integers (0-100)
- CRITICAL — Confidence scoring based on visible features:
  * confidence_level MUST reflect what is actually visible in the image, not what you assume.
  * If ONLY leaves/stems are visible (no flowers, no fruit, no bark texture, no distinctive markings):
    - confidence_level MUST be ≤ 70
    - For tropical trees with similar foliage (e.g. Jackfruit, Water Apple, Guava, Syzygium spp., Rambutan, Longan, Mango): confidence_level MUST be ≤ 60
    - Set low_confidence_reason explaining what is missing
    - image_features MUST list what IS visible (e.g. ["leaves only", "no flowers", "no fruit"])
  * confidence_level ≥ 85 is ONLY allowed when distinctive features are clearly visible:
    - Fruit (ripe or unripe) visible on plant
    - Flowers clearly visible
    - Highly distinctive bark pattern (e.g. papery bark, thorns, corky texture)
    - Unique leaf pattern that is genus/species-specific (e.g. variegation, pinnate vs. simple)
    - Plant has a unique growth form impossible to confuse (e.g. cactus, pandanus, banana)
  * confidence_level 71–84: Some features visible but not definitive
  * confidence_level ≤ 70: Leaf/stem only or ambiguous image
- possible_matches: ALWAYS include this array
  * When confidence_level ≤ 84: include 2-4 alternative species that share similar characteristics
  * When confidence_level ≥ 85: still include 1-2 alternatives for transparency
  * Each entry needs: plant_name, scientific_name, confidence (integer), distinguishing_note
  * For Malaysian tropical fruit trees with similar foliage: ALWAYS list related Syzygium spp., Myrtaceae family members, and other trees with similar leaf shape
  * Confidence values in possible_matches must sum to less than 200 (they are NOT mutually exclusive probabilities)
- image_features: list all visible distinguishing features, e.g. ["leaves only", "compound leaves", "flowers visible", "fruit visible", "distinctive bark", "thorns", "variegated leaves"]
- low_confidence_reason: explain WHY confidence is limited (e.g. "Only leaves visible — Jackfruit and Water Apple share near-identical foliage"). Leave empty string "" if confidence ≥ 85 and identification is certain.
- The suitability_score for purchase_decision MUST reflect ALL of the following factors together, not just climate compatibility:
  1. Climate suitability for Malaysia (tropical heat + humidity)
  2. Commercial availability — can this plant actually be purchased from a Malaysian nursery?
  3. Home gardening practicality — is it realistic for an average Malaysian home gardener?
  4. Maintenance difficulty — hard to maintain plants score lower
  5. Cultivation success rate — plants that rarely survive at home score lower
  6. Special environmental requirements — plants needing host vines, huge ponds, forest conditions, etc. score much lower
  IMPORTANT: Climate suitability alone must NOT generate a high score. A plant that can survive in Malaysia's climate but is practically impossible to cultivate at home (e.g. Rafflesia, giant pitcher plants) must score no higher than 35-40.
- The suitability_score MUST be consistent with the recommendation label:
  * "Not Recommended"    → suitability_score MUST be ≤ 28
  * "Consider Carefully" → suitability_score MUST be 29–55
  * "Recommended"        → suitability_score MUST be 56–74
  * "Highly Recommended" → suitability_score MUST be 75–100
  It is INVALID to give a plant "Not Recommended" and a score of 70. Always match them.
- Plants that require cold dormancy, chilling hours, or winter temperatures (e.g. tulips, crocus, peonies, apples) are NOT suitable for Malaysia and MUST receive:
  * malaysia_suitable: false
  * recommendation: "Not Recommended"
  * suitability_score: 10–25
- advantages, challenges, flower_colors, popular_in_region must be arrays of strings
- advantages and challenges MUST be specific to this exact plant species — mention the plant's actual traits, behaviours, or care needs. Do NOT write generic filler like "Vibrant colors", "Fast-growing", "Requires regular pruning", "Drought-tolerant" unless these are a distinctive defining trait of this species. Each item should be something that would NOT apply to most other plants.
- Do NOT use placeholder text ("Benefit 1", "Challenge 1", etc.). If you cannot identify specific advantages or challenges for this plant, return an empty array [].
- similar_plants must be an array of objects each with "name" (common name string) and "scientific_name" (Latin binomial string)
- popular_varieties must be an array of objects each with name, difficulty, note
- pet_safe must be a boolean true or false
- Use local currency for prices based on user location (default RM for Malaysia)
- If you cannot identify a plant, return: {"error": "No plant detected in the image"}
- Return ONLY the JSON, no extra text or markdown
- malaysia_suitable must be a boolean true or false
- best_location: Evaluate based on REAL Malaysian home gardening practices, NOT just plant type:
  * balcony=true for ANY plant that grows successfully in a pot/container with 3h+ direct sun — this includes ornamental shrubs (Rose, Hibiscus, Ixora, Gardenia), succulents, herbs, orchids, and compact groundcovers. Do NOT mark balcony=false just because a plant is classified as a shrub — most Malaysian ornamental shrubs thrive in containers on sunny balconies.
  * balcony=false ONLY for: large trees requiring deep roots (Rain Tree, Angsana), invasive spreaders (Bamboo, Water Hyacinth), plants requiring full shade that a sunny balcony cannot provide, or aquatic plants needing very large ponds.
  * porch=true for plants tolerating partial/filtered shade and some sun — porches with morning sun work for most ornamental plants.
  * indoor=true only for plants that genuinely thrive in low-light interior conditions (Pothos, Peace Lily, ZZ Plant, Snake Plant, Anthurium, Calathea, ferns).
  * best_location values must all be true or false booleans
- Use Hot Season / Rainy Season instead of Spring/Summer/Autumn/Winter in all text fields
"""


def quick_get_scientific_name(image_base64: str) -> str | None:
    """Cheap pre-check: returns just the scientific name (max 50 tokens) or None."""
    try:
        image_bytes = base64.b64decode(image_base64)
        mime = _detect_mime(image_bytes)
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime};base64,{image_base64}",
                            "detail": "low",
                        },
                    },
                    {
                        "type": "text",
                        "text": (
                            "What is the scientific (Latin) name of the plant in this image? "
                            "Reply with ONLY the scientific name (genus + species), nothing else. "
                            "If no plant is visible, reply with: unknown"
                        ),
                    },
                ],
            }],
            max_tokens=50,
            temperature=0,
        )
        name = response.choices[0].message.content.strip().strip('"').strip("'")
        if not name or name.lower() in ("unknown", "none", "n/a", ""):
            return None
        return name
    except Exception:
        return None


def identify_plant(image_base64: str, garden_profile: dict = None) -> dict:
    image_bytes = base64.b64decode(image_base64)
    mime = _detect_mime(image_bytes)

    prompt = PLANT_PROMPT
    if garden_profile:
        garden_context = (
            f"\n\nUser's garden conditions:\n"
            f"- Location: {garden_profile.get('location', 'Unknown')}\n"
            f"- Garden size: {garden_profile.get('garden_size', 'Unknown')}\n"
            f"- Sunlight: {garden_profile.get('sunlight', 'Unknown')}\n"
            f"- Soil type: {garden_profile.get('soil_type', 'Unknown')}\n"
            f"- Water availability: {garden_profile.get('water_availability', 'Unknown')}\n"
            f"\nTailor the suitability_score and recommendation to these specific garden conditions."
        )
        prompt = PLANT_PROMPT.replace(
            "- Return ONLY the JSON, no extra text or markdown",
            "- Return ONLY the JSON, no extra text or markdown" + garden_context
        )

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime};base64,{image_base64}",
                            "detail": "high",
                        },
                    },
                    {"type": "text", "text": prompt},
                ],
            }
        ],
        max_tokens=2500,
        temperature=0,
    )

    raw = response.choices[0].message.content.strip()

    # Strip markdown code blocks if present
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]

    result = json.loads(raw)

    # ── Post-processing: enforce confidence caps & low-confidence warnings ──
    _enforce_confidence(result)

    return result


def identify_plant_multi(images: list[dict], garden_profile: dict = None) -> dict:
    """
    Multi-photo identification.
    images: list of {"image_base64": str, "type": "leaf"|"stem"|"flower"}
    Images are sorted so flower/fruit first (most diagnostic).
    """
    prompt = PLANT_PROMPT
    if garden_profile:
        garden_context = (
            f"\n\nUser's garden conditions:\n"
            f"- Location: {garden_profile.get('location', 'Unknown')}\n"
            f"- Garden size: {garden_profile.get('garden_size', 'Unknown')}\n"
            f"- Sunlight: {garden_profile.get('sunlight', 'Unknown')}\n"
            f"- Soil type: {garden_profile.get('soil_type', 'Unknown')}\n"
            f"- Water availability: {garden_profile.get('water_availability', 'Unknown')}\n"
            f"\nTailor the suitability_score and recommendation to these specific garden conditions."
        )
        prompt = PLANT_PROMPT.replace(
            "- Return ONLY the JSON, no extra text or markdown",
            "- Return ONLY the JSON, no extra text or markdown" + garden_context
        )

    # Sort: flower first, then leaf, then stem (most to least diagnostic)
    _type_order = {"flower": 0, "fruit": 0, "leaf": 1, "stem": 2}
    sorted_images = sorted(images, key=lambda x: _type_order.get(x.get("type", "leaf"), 1))

    photo_types = [img.get("type", "leaf") for img in sorted_images]
    type_labels = {"flower": "Flower/Fruit", "fruit": "Flower/Fruit", "leaf": "Leaf", "stem": "Stem/Trunk"}
    photos_desc = ", ".join(type_labels.get(t, t.capitalize()) for t in photo_types)

    weighting_note = (
        f"MULTI-PHOTO IDENTIFICATION: {len(sorted_images)} images provided ({photos_desc}). "
        "Analyze ALL images together for maximum accuracy. "
        "Identification weighting: Flower/Fruit images carry 50% weight, Leaf images 30%, Stem/Trunk 20%. "
        "If a flower or fruit image is present, it should strongly dominate your identification decision. "
        "Your image_features field MUST list features from ALL provided images combined.\n\n"
    )

    content = []
    for img_data in sorted_images:
        img_b64 = img_data["image_base64"]
        img_type = img_data.get("type", "leaf")
        image_bytes = base64.b64decode(img_b64)
        mime = _detect_mime(image_bytes)
        label = type_labels.get(img_type, img_type.capitalize())
        content.append({
            "type": "text",
            "text": f"[Image: {label}]",
        })
        content.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:{mime};base64,{img_b64}",
                "detail": "high",
            },
        })

    content.append({"type": "text", "text": weighting_note + prompt})

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": content}],
        max_tokens=2500,
        temperature=0,
    )

    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]

    result = json.loads(raw)
    _enforce_confidence(result)
    return result


def _enforce_confidence(result: dict) -> None:
    """
    Server-side enforcement of confidence rules:
    - Caps confidence at 70 when image_features indicates leaf/stem only
    - Caps confidence at 60 for ambiguous tropical fruit trees with similar foliage
    - Injects a low_confidence_notice into identification when confidence < 85
    - Ensures possible_matches is always present
    """
    ident = result.get("identification", {})
    if not isinstance(ident, dict):
        return

    confidence = ident.get("confidence_level", 100)
    image_features = ident.get("image_features", [])
    low_conf_reason = ident.get("low_confidence_reason", "")

    # Detect leaf-only scenarios
    features_str = " ".join(str(f).lower() for f in image_features)
    is_leaf_only = (
        ("leaves only" in features_str or "leaf only" in features_str)
        or (
            "flower" not in features_str
            and "fruit" not in features_str
            and "bark" not in features_str
            and len(image_features) > 0
        )
    )

    # Detect confusable tropical fruit tree genera
    plant_name_lower = (ident.get("plant_name") or "").lower()
    sci_name_lower = (ident.get("scientific_name") or "").lower()
    confusable_families = [
        "syzygium", "psidium", "artocarpus", "eugenia", "myrtaceae",
        "nephelium", "litchi", "dimocarpus", "mangifera", "annona",
        "water apple", "guava", "jackfruit", "rambutan", "longan",
        "lychee", "mango", "soursop", "custard apple", "jambu",
    ]
    is_confusable = any(k in plant_name_lower or k in sci_name_lower
                        for k in confusable_families)

    # Apply caps
    if is_confusable and is_leaf_only and confidence > 60:
        confidence = 60
        ident["confidence_level"] = 60
        if not low_conf_reason:
            ident["low_confidence_reason"] = (
                f"Only leaves visible — {ident.get('plant_name', 'this species')} shares "
                "near-identical foliage with related tropical trees (Water Apple, Guava, "
                "Syzygium spp.). Fruit or flowers required for reliable identification."
            )
    elif is_leaf_only and confidence > 70:
        confidence = 70
        ident["confidence_level"] = 70
        if not low_conf_reason:
            ident["low_confidence_reason"] = (
                "Only leaves/stems visible — confidence capped. "
                "Provide an image with flowers, fruit, or distinctive bark for higher accuracy."
            )

    # Inject low_confidence_notice for the app UI
    if confidence < 85:
        matches = result.get("possible_matches", [])
        if not isinstance(matches, list):
            matches = []
        notice_parts = []
        if low_conf_reason:
            notice_parts.append(low_conf_reason)
        if matches:
            alts = ", ".join(
                f"{m.get('plant_name', '?')} ({m.get('confidence', '?')}%)"
                for m in matches[:3]
            )
            notice_parts.append(f"Other possible matches: {alts}.")
        ident["low_confidence_notice"] = " ".join(notice_parts) if notice_parts else (
            "Identification confidence is below 85%. Consider re-scanning with better lighting "
            "or a clearer image showing flowers or fruit."
        )
    else:
        ident["low_confidence_notice"] = ""

    # Ensure possible_matches always exists
    if "possible_matches" not in result:
        result["possible_matches"] = []


# ── Disease Diagnosis ─────────────────────────────────────────────────────────

DISEASE_PROMPT = """
You are diagnosing a plant for a Malaysian gardener. Malaysia has a tropical climate (26-35°C, high humidity) with Hot Season and Rainy Season — use these instead of spring/summer/autumn/winter in any care advice.

Analyze this plant image carefully for diseases, pests, nutrient deficiencies, or environmental stress.

Return ONLY a valid JSON object with this exact structure:
{
  "plant": {
    "name": "Common plant name",
    "scientific_name": "Scientific name or null"
  },
  "diagnosis": {
    "status": "Healthy",
    "disease_name": "None",
    "disease_type": "None",
    "severity": "None",
    "confidence": 90,
    "affected_parts": [],
    "symptoms": ["Plant appears healthy with no visible issues"],
    "description": "The plant shows no signs of disease, pest damage, or nutrient deficiency."
  },
  "causes": [],
  "treatment": {
    "immediate_actions": [],
    "products": [],
    "application": "N/A",
    "recovery_time": "N/A"
  },
  "prevention": ["Continue regular watering", "Monitor for early signs of stress"],
  "urgency": "Healthy"
}

Rules:
- status: Healthy / Diseased / Pest Infestation / Nutrient Deficiency / Environmental Stress
- disease_type: Fungal / Bacterial / Viral / Pest / Deficiency / Abiotic / None
- severity: None / Mild / Moderate / Severe
- urgency: Healthy / Low Priority / Monitor / Act Soon / Act Now
- confidence: integer 0-100
- All list fields must be arrays of strings
- If healthy: status="Healthy", disease_name="None", severity="None", urgency="Healthy"
- Return ONLY the JSON, no extra text or markdown
- If no plant is visible, return: {"error": "No plant detected in the image"}
- Use Hot Season / Rainy Season instead of Spring/Summer/Autumn/Winter
"""


def diagnose_disease(image_base64: str, hint_plant_name: str = None, hint_scientific_name: str = None) -> dict:
    image_bytes = base64.b64decode(image_base64)
    mime = _detect_mime(image_bytes)

    prompt = DISEASE_PROMPT
    if hint_plant_name or hint_scientific_name:
        plant_ctx = hint_plant_name or ''
        sci_ctx   = hint_scientific_name or ''
        plant_line = f'  - This plant is: {plant_ctx}'
        if sci_ctx:
            plant_line += f' ({sci_ctx})'
        plant_line += '.'
        # Inject into prompt before the Rules section
        prompt = prompt.replace(
            'Rules:',
            f'IMPORTANT — Plant identity hint provided by the user:\n{plant_line}\n'
            f'Your diagnosis MUST be specific to this plant. Do NOT mention or reference any other species.\n\nRules:'
        )

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime};base64,{image_base64}",
                        "detail": "high",
                    },
                },
                {"type": "text", "text": prompt},
            ],
        }],
        max_tokens=1500,
        temperature=0,
    )

    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw)
