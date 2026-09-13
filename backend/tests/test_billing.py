from datetime import datetime, timezone

from app.billing import subscription_change


def event(status="active", event_type="customer.subscription.updated"):
    return {
        "id": "evt_1",
        "type": event_type,
        "data": {
            "object": {
                "id": "sub_1",
                "customer": "cus_1",
                "status": status,
                "current_period_end": 1790985600,
            }
        },
    }


def test_active_stripe_subscription_grants_pro_until_period_end():
    customer, subscription, active, expiry = subscription_change(event())
    assert (customer, subscription, active) == ("cus_1", "sub_1", True)
    assert expiry == datetime.fromtimestamp(1790985600, tz=timezone.utc)


def test_deleted_or_unpaid_subscription_revokes_pro():
    assert subscription_change(event(status="unpaid"))[2] is False
    assert subscription_change(event(status="trialing"))[2] is False
    assert subscription_change(
        event(status="canceled", event_type="customer.subscription.deleted")
    )[2] is False


def test_unrelated_webhook_does_not_change_entitlement():
    assert subscription_change(event(event_type="invoice.paid")) == (
        None,
        None,
        None,
        None,
    )
