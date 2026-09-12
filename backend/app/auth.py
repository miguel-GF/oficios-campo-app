from dataclasses import dataclass
from datetime import datetime

import httpx
from fastapi import Header, HTTPException

from .config import get_settings


@dataclass(frozen=True)
class Account:
    user_id: str
    email: str
    registered_period: str | None = None


def registration_period(created_at: str | None) -> str | None:
    if not created_at:
        return None
    try:
        return datetime.fromisoformat(created_at.replace("Z", "+00:00")).strftime(
            "%Y-%m"
        )
    except (TypeError, ValueError):
        return None


async def optional_account(authorization: str | None = Header(default=None)) -> Account | None:
    if not authorization:
        return None
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="AUTH_INVALID")
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_anon_key:
        raise HTTPException(status_code=503, detail="AUTH_NOT_CONFIGURED")
    async with httpx.AsyncClient(timeout=8) as client:
        response = await client.get(
            f"{settings.supabase_url.rstrip('/')}/auth/v1/user",
            headers={
                "Authorization": authorization,
                "apikey": settings.supabase_anon_key,
            },
        )
    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="AUTH_INVALID")
    payload = response.json()
    registered_period = registration_period(payload.get("created_at"))
    return Account(
        user_id=payload["id"],
        email=payload.get("email") or "",
        registered_period=registered_period,
    )
