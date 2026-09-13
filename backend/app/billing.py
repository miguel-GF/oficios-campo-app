from datetime import datetime, timezone

import stripe
from anyio import to_thread

from .auth import Account
from .config import Settings
from .database import CreditStore
from .models import BillingPlan


def _configure(settings: Settings) -> None:
    if not settings.stripe_secret_key:
        raise RuntimeError("STRIPE_NOT_CONFIGURED")
    stripe.api_key = settings.stripe_secret_key


async def list_plans(settings: Settings) -> list[BillingPlan]:
    _configure(settings)
    configured = [
        ("monthly", settings.stripe_monthly_price_id),
        ("yearly", settings.stripe_yearly_price_id),
    ]
    if any(not price_id for _, price_id in configured):
        raise RuntimeError("STRIPE_PRICES_NOT_CONFIGURED")
    plans: list[BillingPlan] = []
    for plan_id, price_id in configured:
        price = await to_thread.run_sync(lambda value=price_id: stripe.Price.retrieve(value))
        recurring = price.get("recurring") or {}
        plans.append(
            BillingPlan(
                id=plan_id,
                price_id=price_id,
                unit_amount=int(price.get("unit_amount") or 0),
                currency=str(price.get("currency") or "mxn").upper(),
                interval=str(recurring.get("interval") or ("year" if plan_id == "yearly" else "month")),
            )
        )
    return plans


async def checkout_url(
    settings: Settings,
    store: CreditStore,
    account: Account,
    plan: str,
) -> str:
    _configure(settings)
    price_id = (
        settings.stripe_yearly_price_id
        if plan == "yearly"
        else settings.stripe_monthly_price_id
    )
    if not price_id:
        raise RuntimeError("STRIPE_PRICES_NOT_CONFIGURED")
    customer_id = await store.stripe_customer_for(account)
    if customer_id is None:
        customer = await to_thread.run_sync(
            lambda: stripe.Customer.create(
                email=account.email,
                metadata={"jale_user_id": account.user_id},
            )
        )
        customer_id = customer.id
        await store.bind_stripe_customer(account, customer_id)
    session = await to_thread.run_sync(
        lambda: stripe.checkout.Session.create(
            mode="subscription",
            customer=customer_id,
            client_reference_id=account.user_id,
            line_items=[{"price": price_id, "quantity": 1}],
            success_url=settings.stripe_success_url,
            cancel_url=settings.stripe_cancel_url,
            allow_promotion_codes=True,
            subscription_data={"metadata": {"jale_user_id": account.user_id}},
        )
    )
    return session.url


async def portal_url(
    settings: Settings,
    store: CreditStore,
    account: Account,
) -> str:
    _configure(settings)
    customer_id = await store.stripe_customer_for(account)
    if customer_id is None:
        raise RuntimeError("STRIPE_CUSTOMER_NOT_FOUND")
    session = await to_thread.run_sync(
        lambda: stripe.billing_portal.Session.create(
            customer=customer_id,
            return_url=settings.stripe_portal_return_url,
        )
    )
    return session.url


def parse_webhook(settings: Settings, body: bytes, signature: str) -> dict:
    if not settings.stripe_webhook_secret:
        raise RuntimeError("STRIPE_WEBHOOK_NOT_CONFIGURED")
    event = stripe.Webhook.construct_event(
        payload=body,
        sig_header=signature,
        secret=settings.stripe_webhook_secret,
    )
    return event.to_dict_recursive()


def subscription_change(event: dict) -> tuple[str | None, str | None, bool | None, datetime | None]:
    if event.get("type") not in {
        "customer.subscription.created",
        "customer.subscription.updated",
        "customer.subscription.deleted",
    }:
        return None, None, None, None
    subscription = event["data"]["object"]
    customer_id = subscription.get("customer")
    subscription_id = subscription.get("id")
    active = subscription.get("status") == "active"
    period_end = subscription.get("current_period_end")
    if period_end is None:
        items = (subscription.get("items") or {}).get("data") or []
        period_end = items[0].get("current_period_end") if items else None
    pro_until = (
        datetime.fromtimestamp(int(period_end), tz=timezone.utc)
        if period_end
        else None
    )
    return customer_id, subscription_id, active, pro_until
