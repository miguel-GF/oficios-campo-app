from datetime import datetime, timezone
import base64
import hashlib

from app.billing import subscription_verdict
from app.config import Settings


NOW = datetime(2026, 9, 3, tzinfo=timezone.utc)


def payload(*, account="user-1", state="SUBSCRIPTION_STATE_ACTIVE", expiry="2026-10-03T00:00:00Z"):
    account = base64.urlsafe_b64encode(hashlib.sha256(account.encode()).digest()).decode().rstrip("=")
    return {
        "externalAccountIdentifiers": {"obfuscatedExternalAccountId": account},
        "subscriptionState": state,
        "lineItems": [
            {
                "productId": "jale_pro",
                "expiryTime": expiry,
                "offerDetails": {"basePlanId": "mensual"},
            }
        ],
    }


def test_active_purchase_is_bound_to_the_jale_account():
    active, _, plan, audit = subscription_verdict(
        payload(), Settings(), "user-1", NOW
    )
    assert active is True
    assert plan == "mensual"
    assert audit["account_bound"] is True


def test_purchase_from_another_account_is_rejected():
    active, expiry, plan, audit = subscription_verdict(
        payload(account="attacker"), Settings(), "user-1", NOW
    )
    assert (active, expiry, plan) == (False, None, None)
    assert audit["verification_status"] == "account_mismatch"


def test_expired_or_on_hold_subscription_is_not_pro():
    assert subscription_verdict(
        payload(expiry="2026-08-01T00:00:00Z"), Settings(), "user-1", NOW
    )[0] is False
    assert subscription_verdict(
        payload(state="SUBSCRIPTION_STATE_ON_HOLD"), Settings(), "user-1", NOW
    )[0] is False
