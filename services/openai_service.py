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
    "description": "2-3 sentence description of the plant"
  },
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

    return json.loads(raw)


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
