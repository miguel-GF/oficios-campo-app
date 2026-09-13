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


def _allowed_versions(value: str) -> set[int]:
    try:
        return {int(item.strip()) for item in value.split(",") if item.strip()}
    except ValueError as error:
        raise HTTPException(status_code=503, detail="INTEGRITY_NOT_CONFIGURED") from error


async def verify_app_integrity(request: Request, settings: Settings) -> None:
    token = request.headers.get("x-play-integrity", "")
    supplied_hash = request.headers.get("x-request-hash", "")
    distribution = request.headers.get("x-jale-distribution", "")
    if distribution not in {"direct", "play"}:
        raise HTTPException(status_code=403, detail="DISTRIBUTION_INVALID")
    if not token:
        if settings.require_app_integrity:
            raise HTTPException(status_code=403, detail="INTEGRITY_REQUIRED")
        return

    expected_hash = request_hash(await request.body())
    if supplied_hash != expected_hash:
        raise HTTPException(status_code=403, detail="REQUEST_TAMPERED")
    if not settings.google_service_account_json:
        raise HTTPException(status_code=503, detail="INTEGRITY_NOT_CONFIGURED")

    package_name = (
        settings.play_android_package
        if distribution == "play"
        else settings.direct_android_package
    )
    expected_certificate = (
        settings.play_certificate_sha256
        if distribution == "play"
        else settings.direct_certificate_sha256
    )
    allowed_versions = _allowed_versions(
        settings.play_version_codes
        if distribution == "play"
        else settings.direct_version_codes
    )
    if not package_name or not expected_certificate or not allowed_versions:
        raise HTTPException(status_code=503, detail="INTEGRITY_NOT_CONFIGURED")

    info = json.loads(settings.google_service_account_json)
    credentials = service_account.Credentials.from_service_account_info(
        info,
        scopes=["https://www.googleapis.com/auth/playintegrity"],
    )
    await asyncio.to_thread(credentials.refresh, GoogleAuthRequest())
    url = (
        "https://playintegrity.googleapis.com/v1/"
        f"{package_name}:decodeIntegrityToken"
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
    account = verdict.get("accountDetails", {})
    if details.get("requestHash") != expected_hash:
        raise HTTPException(status_code=403, detail="REQUEST_TAMPERED")
    if details.get("requestPackageName") != package_name:
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    timestamp = datetime.fromtimestamp(
        int(details.get("timestampMillis", 0)) / 1000, timezone.utc
    )
    if abs((datetime.now(timezone.utc) - timestamp).total_seconds()) > 120:
        raise HTTPException(status_code=403, detail="INTEGRITY_EXPIRED")

    recognition = app.get("appRecognitionVerdict")
    if distribution == "play" and recognition != "PLAY_RECOGNIZED":
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    if distribution == "direct" and recognition not in {
        "PLAY_RECOGNIZED",
        "UNRECOGNIZED_VERSION",
    }:
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    if app.get("packageName") != package_name:
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    certificates = set(app.get("certificateSha256Digest") or [])
    if expected_certificate not in certificates:
        raise HTTPException(status_code=403, detail="APP_UNRECOGNIZED")
    if int(app.get("versionCode") or 0) not in allowed_versions:
        raise HTTPException(status_code=403, detail="APP_VERSION_DENIED")
    if distribution == "play" and account.get("appLicensingVerdict") != "LICENSED":
        raise HTTPException(status_code=403, detail="APP_UNLICENSED")
    device_verdicts = device.get("deviceRecognitionVerdict") or []
    if "MEETS_DEVICE_INTEGRITY" not in device_verdicts:
        raise HTTPException(status_code=403, detail="DEVICE_UNTRUSTED")
