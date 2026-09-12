import asyncio
import json
import base64
import hashlib
from datetime import datetime, timezone
from urllib.parse import quote

import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account

from .config import Settings


ACTIVE_STATES = {
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
}


def subscription_verdict(
    payload: dict,
    settings: Settings,
    account_user_id: str,
    current_time: datetime | None = None,
):
    external_ids = payload.get("externalAccountIdentifiers") or {}
    purchase_account = external_ids.get("obfuscatedExternalAccountId")
    expected_account = base64.urlsafe_b64encode(
        hashlib.sha256(account_user_id.encode()).digest()
    ).decode().rstrip("=")
    if purchase_account != expected_account:
        return False, None, None, {"verification_status": "account_mismatch"}
    state = payload.get("subscriptionState", "")
    line_items = payload.get("lineItems") or []
    matching = [item for item in line_items if item.get("productId") == settings.play_product_id]
    if not matching:
        return False, None, None, {"subscription_state": state}
    expiry_values = [item.get("expiryTime") for item in matching if item.get("expiryTime")]
    if not expiry_values:
        return False, None, None, {"subscription_state": state}
    expiry = max(datetime.fromisoformat(value.replace("Z", "+00:00")) for value in expiry_values)
    active = state in ACTIVE_STATES and expiry > (
        current_time or datetime.now(timezone.utc)
    )
    base_plan = matching[-1].get("offerDetails", {}).get("basePlanId")
    audit = {
        "subscription_state": state,
        "base_plan_id": base_plan,
        "account_bound": True,
    }
    return active, expiry, base_plan, audit


async def verify_google_subscription(
    settings: Settings, purchase_token: str, account_user_id: str
):
    if not settings.google_play_service_account_json:
        raise RuntimeError("PLAY_NOT_CONFIGURED")
    info = json.loads(settings.google_play_service_account_json)
    credentials = service_account.Credentials.from_service_account_info(
        info,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    await asyncio.to_thread(credentials.refresh, GoogleAuthRequest())
    url = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/"
        f"applications/{settings.android_package_name}/purchases/subscriptionsv2/"
        f"tokens/{quote(purchase_token, safe='')}"
    )
    async with httpx.AsyncClient(timeout=12) as client:
        response = await client.get(
            url,
            headers={"Authorization": f"Bearer {credentials.token}"},
        )
    if response.status_code != 200:
        return False, None, None, {"verification_status": response.status_code}
    return subscription_verdict(response.json(), settings, account_user_id)
