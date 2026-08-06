"""AI gateway: OpenAI primary, Claude fallback. Used for coaching, meal plans, vision."""
import base64
import json
import logging
from typing import Any, Dict, List, Optional
 
from anthropic import AsyncAnthropic
from openai import AsyncOpenAI
 
from app.core.config import settings
 
logger = logging.getLogger(__name__)
 
def _make_openai_client() -> Optional[AsyncOpenAI]:
    if not settings.OPENAI_API_KEY:
        return None
    kwargs = {"api_key": settings.OPENAI_API_KEY}
    if settings.OPENAI_BASE_URL:
        kwargs["base_url"] = settings.OPENAI_BASE_URL
    return AsyncOpenAI(**kwargs)
 
 
_openai: Optional[AsyncOpenAI] = _make_openai_client()
_anthropic: Optional[AsyncAnthropic] = (
    AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY) if settings.ANTHROPIC_API_KEY else None
)
 
 
class AIUnavailable(RuntimeError):
    pass
 
 
COACH_SYSTEM = """You are the AI coach inside a weight-loss app. You are supportive, practical and evidence-based.
 
Rules you never break:
- Never recommend a daily intake below 1200 kcal for women or 1500 kcal for men.
- Never recommend losing more than 1 kg (2 lb) per week.
- Never endorse purging, fasting beyond 24h, appetite-suppressant misuse, or "earning" food through exercise.
- If the user describes disordered eating, self-harm, or extreme restriction, drop the coaching tone, respond with
  care, and encourage them to speak with a doctor or a qualified professional. Do not give numeric targets in that turn.
- You are not a doctor. For medical conditions, pregnancy, or medication questions, tell the user to consult a clinician.
- Keep answers under 180 words unless asked for detail. Reference the user's real data when it is provided.
"""
 
 
def _messages_for_openai(system: str, messages: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    return [{"role": "system", "content": system}] + [
        {"role": m["role"], "content": m["content"]} for m in messages
    ]
 
 
async def chat(
    messages: List[Dict[str, str]],
    system: str = COACH_SYSTEM,
    max_tokens: int = 800,
    temperature: float = 0.6,
) -> tuple[str, str]:
    """Returns (text, provider)."""
    order = ["openai", "anthropic"] if settings.AI_PRIMARY == "openai" else ["anthropic", "openai"]
    last_error: Optional[Exception] = None
 
    for provider in order:
        try:
            if provider == "openai" and _openai:
                resp = await _openai.chat.completions.create(
                    model=settings.OPENAI_MODEL,
                    messages=_messages_for_openai(system, messages),
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
                return resp.choices[0].message.content or "", "openai"
            if provider == "anthropic" and _anthropic:
                resp = await _anthropic.messages.create(
                    model=settings.ANTHROPIC_MODEL,
                    system=system,
                    messages=[{"role": m["role"], "content": m["content"]} for m in messages],
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
                return "".join(b.text for b in resp.content if b.type == "text"), "anthropic"
        except Exception as exc:  # pragma: no cover - network path
            last_error = exc
            logger.warning("AI provider %s failed: %s", provider, exc)
 
    raise AIUnavailable(str(last_error) if last_error else "no AI provider configured")
 
 
async def chat_json(
    messages: List[Dict[str, str]], system: str, max_tokens: int = 3000
) -> Dict[str, Any]:
    text, _ = await chat(messages, system=system, max_tokens=max_tokens, temperature=0.3)
    return parse_json(text)
 
 
def parse_json(text: str) -> Dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("```")[1]
        if cleaned.startswith("json"):
            cleaned = cleaned[4:]
    cleaned = cleaned.strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("model did not return JSON")
    return json.loads(cleaned[start : end + 1])
 
 
VISION_SYSTEM = """You estimate nutrition from a food photo. Respond with JSON only, no prose:
{"items":[{"name":str,"quantity_g":number,"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"confidence":0-1}],
"notes":str}
Estimate realistic portion sizes from visual cues (plate size, utensils). If no food is visible, return an empty items array
and explain that in notes. Never return zero calories for a visible food."""
 
 
async def analyze_food_image(image_bytes: bytes, mime: str = "image/jpeg", hint: str = "") -> Dict[str, Any]:
    b64 = base64.b64encode(image_bytes).decode()
    prompt = "Analyse this meal photo and estimate the nutrition."
    if hint:
        prompt += f" User hint: {hint}"
 
    order = ["openai", "anthropic"] if settings.AI_PRIMARY == "openai" else ["anthropic", "openai"]
    last_error: Optional[Exception] = None
 
    for provider in order:
        try:
            if provider == "openai" and _openai:
                resp = await _openai.chat.completions.create(
                    model=settings.OPENAI_VISION_MODEL,
                    messages=[
                        {"role": "system", "content": VISION_SYSTEM},
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
                            ],
                        },
                    ],
                    max_tokens=1200,
                    temperature=0.2,
                )
                return parse_json(resp.choices[0].message.content or "")
            if provider == "anthropic" and _anthropic:
                resp = await _anthropic.messages.create(
                    model=settings.ANTHROPIC_MODEL,
                    system=VISION_SYSTEM,
                    max_tokens=1200,
                    temperature=0.2,
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "image",
                                    "source": {"type": "base64", "media_type": mime, "data": b64},
                                },
                                {"type": "text", "text": prompt},
                            ],
                        }
                    ],
                )
                return parse_json("".join(b.text for b in resp.content if b.type == "text"))
        except Exception as exc:  # pragma: no cover - network path
            last_error = exc
            logger.warning("Vision provider %s failed: %s", provider, exc)
 
    raise AIUnavailable(str(last_error) if last_error else "no AI provider configured")
