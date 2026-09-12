import asyncio
import base64
import hashlib
import json
from datetime import datetime, timezone

import httpx
from fastapi import HTTPException, Request
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account

from .config import Settings


def request_hash(body: bytes) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(body).digest()).decode().rstrip("=")


async def verify_play_integrity(request: Request, settings: Settings) -> None:
    token = request.headers.get("x-play-integrity", "")
    supplied_hash = request.headers.get("x-request-hash", "")
    if not token:
        if settings.require_play_integrity:
            raise HTTPException(status_code=403, detail="INTEGRITY_REQUIRED")
        return

    expected_hash = request_hash(await request.body())
    if supplied_hash != expected_hash:
        raise HTTPException(status_code=403, detail="REQUEST_TAMPERED")
    if not settings.google_play_service_account_json:
        raise HTTPException(status_code=503, detail="INTEGRITY_NOT_CONFIGURED")

    info = json.loads(settings.google_play_service_account_json)
    credentials = service_account.Credentials.from_service_account_info(
        info,
        scopes=["https://www.googleapis.com/auth/playintegrity"],
    )
    await asyncio.to_thread(credentials.refresh, GoogleAuthRequest())
    url = (
        "https://playintegrity.googleapis.com/v1/"
        f"{settings.android_package_name}:decodeIntegrityToken"
    )
    async with httpx.AsyncClient(timeout=12) as client:
        response = await client.post(
            url,
            headers={"Authorization": f"Bearer {credentials.token}"},
            json={"integrity_token": token},
        )
    if response.status_code != 200:
        raise HTTPException(status_code=403, detail="INTEGRITY_INVALID")

    verdict = response.json().get("tokenPayloadExternal", {})
    details = verdict.get("requestDetails", {})
    app = verdict.get("appIntegrity", {})
    device = verdict.get("deviceIntegrity", {})
    if details.get("requestHash") != expected_hash:
        raise HTTPException(status_code=403, detail="REQUEST_TAMPERED")
    if details.get("requestPackageName") != settings.android_package_name:
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    timestamp = datetime.fromtimestamp(
        int(details.get("timestampMillis", 0)) / 1000, timezone.utc
    )
    if abs((datetime.now(timezone.utc) - timestamp).total_seconds()) > 120:
        raise HTTPException(status_code=403, detail="INTEGRITY_EXPIRED")
    if app.get("appRecognitionVerdict") != "PLAY_RECOGNIZED":
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    device_verdicts = device.get("deviceRecognitionVerdict") or []
    if "MEETS_DEVICE_INTEGRITY" not in device_verdicts:
        raise HTTPException(status_code=403, detail="DEVICE_UNTRUSTED")
