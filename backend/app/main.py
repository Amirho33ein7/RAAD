from __future__ import annotations

import os
import time
from typing import Any
from urllib.parse import quote

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()
APP_NAME = "رعد | RAAD API"
PROVIDER_BASE_URL = os.getenv("CODM_API_BASE_URL", "https://callofdutymobile.vercel.app").rstrip("/")
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "10"))
CACHE_TTL = max(0, int(os.getenv("PROFILE_CACHE_TTL_SECONDS", "300")))

app = FastAPI(title=APP_NAME, description="درگاه آزمایشی برای داده‌های قابل‌دسترسی پروفایل CODM؛ سرویس خارجی غیررسمی است.", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["http://localhost", "http://127.0.0.1"], allow_credentials=False, allow_methods=["GET"], allow_headers=["*"])

_cache: dict[str, tuple[float, dict[str, Any]]] = {}
_ALLOWED_FIELDS = ("nickname", "level", "picUrl", "rankClass", "customReadableMpRank", "customMpRankImageUrl", "rating", "shortId", "country", "countryId")


def _normalize_profile(payload: Any) -> dict[str, Any]:
    """Keep only documented fields that are actually present; never synthesize stats."""
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="پاسخ سرویس پروفایل قابل‌فهم نیست.")
    candidate: Any = payload
    for key in ("data", "user", "profile"):
        if isinstance(candidate, dict) and isinstance(candidate.get(key), dict):
            candidate = candidate[key]
            break
    result = {key: candidate[key] for key in _ALLOWED_FIELDS if key in candidate and candidate[key] is not None}
    if not result:
        raise HTTPException(status_code=502, detail="سرویس پاسخ داد، اما فیلد پروفایل قابل‌استفاده‌ای برنگرداند.")
    result["data_source"] = "unofficial"
    result["retrieved_at_unix"] = int(time.time())
    return result


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "raad-api", "provider": "unofficial"}


@app.get("/api/v1/codm/profile")
async def get_profile(q: str = Query(min_length=1, max_length=80, description="نام یا شناسهٔ بازیکن")) -> dict[str, Any]:
    query = q.strip()
    if not query or any(ord(ch) < 32 for ch in query):
        raise HTTPException(status_code=400, detail="نام یا شناسه معتبر نیست.")
    key = query.casefold()
    now = time.time()
    cached = _cache.get(key)
    if cached and now - cached[0] < CACHE_TTL:
        return {**cached[1], "cache": "hit"}
    url = f"{PROVIDER_BASE_URL}/user/{quote(query, safe='')}"
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT, follow_redirects=False) as client:
            response = await client.get(url, headers={"Accept": "application/json", "User-Agent": "RAAD-Companion/0.1"})
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=504, detail="مهلت پاسخ سرویس پروفایل تمام شد. کمی بعد دوباره تلاش کن.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="ارتباط با سرویس پروفایل برقرار نشد.") from exc
    if response.status_code == 404:
        raise HTTPException(status_code=404, detail="پروفایلی پیدا نشد یا سرویس آن را ارائه نمی‌کند.")
    if response.status_code == 429:
        raise HTTPException(status_code=429, detail="سرویس درخواست‌های زیادی دریافت کرده؛ بعداً دوباره تلاش کن.")
    if response.status_code >= 500:
        raise HTTPException(status_code=502, detail="سرویس پروفایل موقتاً در دسترس نیست.")
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"سرویس پروفایل پاسخ خطا داد (HTTP {response.status_code}).")
    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="پاسخ سرویس JSON معتبر نیست.") from exc
    profile = _normalize_profile(payload)
    _cache[key] = (now, profile)
    return {**profile, "cache": "miss"}


@app.get("/api/v1/capabilities")
def capabilities() -> dict[str, Any]:
    return {
        "provider": "unofficial",
        "profile_lookup": True,
        "documented_fields": list(_ALLOWED_FIELDS),
        "automatic_match_history": False,
        "kills_deaths_wins": False,
        "weapon_inventory": False,
        "note_fa": "فقط فیلدهایی که سرویس خارجی واقعاً برمی‌گرداند نمایش داده می‌شوند؛ تاریخچهٔ مسابقات، کیل، دث و موجودی کامل آیتم‌ها در این نسخه تضمین نشده‌اند."
    }
