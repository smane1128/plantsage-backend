from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from openai import OpenAI, RateLimitError, AuthenticationError
from dotenv import load_dotenv
from utils.rate_limit import check_ai_rate_limit
import os
import json

load_dotenv()

router = APIRouter(prefix="/chat", tags=["chat"])

_openai_client: OpenAI | None = None


def _get_client() -> OpenAI:
    """Lazy-initialise OpenAI client so a missing API key raises at call time, not startup."""
    global _openai_client
    if _openai_client is None:
        key = os.getenv("OPENAI_API_KEY")
        if not key:
            raise HTTPException(status_code=500, detail="OpenAI API key not configured.")
        _openai_client = OpenAI(api_key=key)
    return _openai_client


class ChatMessage(BaseModel):
    role: str   # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    plant_data: dict
    message: str
    history: Optional[List[ChatMessage]] = []


@router.post("")
def chat_with_expert(request: ChatRequest):
    check_ai_rate_limit()
    identification = request.plant_data.get("identification", {})
    plant_name = identification.get("plant_name", "Unknown plant")
    scientific_name = identification.get("scientific_name", "")

    system_prompt = f"""You are an expert botanist and gardening advisor for Malaysian gardeners.

Malaysian growing context:
- Tropical climate: year-round warmth (26-35°C) and high humidity (70-90%)
- Seasons: Hot/Dry Season (approx. Mar-Oct) and Rainy/Monsoon Season (approx. Oct-Feb)
- No spring, summer, autumn, or winter — use Hot Season / Rainy Season in all advice
- Currency: Malaysian Ringgit (RM)
- Common garden spaces: balcony, porch, front yard, terrace house garden, indoor

Plant being discussed:
- Common Name: {plant_name}
- Scientific Name: {scientific_name}
- Full data: {json.dumps(request.plant_data, indent=2)}

Answer questions about this plant clearly and helpfully in the context of Malaysian gardening. Be concise (2-4 sentences unless more detail is needed).
If the question is unrelated to plants or gardening, politely redirect to plant topics."""

    messages = [{"role": "system", "content": system_prompt}]
    for msg in (request.history or []):
        messages.append({"role": msg.role, "content": msg.content})
    messages.append({"role": "user", "content": request.message})

    try:
        response = _get_client().chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            max_tokens=400,
        )
        reply = response.choices[0].message.content.strip()
        return {"reply": reply}
    except RateLimitError:
        raise HTTPException(status_code=402, detail="OpenAI quota exceeded.")
    except AuthenticationError:
        raise HTTPException(status_code=401, detail="Invalid OpenAI API key.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
