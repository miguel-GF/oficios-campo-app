import hashlib
import hmac
from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from .ai import AiProviderError, interpret_quote
from .auth import Account, bearer_value
from .billing import checkout_url, list_plans, parse_webhook, portal_url, subscription_change
from .config import get_settings
from .database import CreditStore, CreditUnavailable
from .integrity import verify_app_integrity
from .models import (
    AuthCodeRequest,
    AuthCodeResponse,
    AuthExchangeRequest,
    AuthLogoutRequest,
    AuthRefreshRequest,
    AuthSessionResponse,
    BillingPlan,
    BillingSessionResponse,
    CheckoutRequest,
    CreditState,
    InterpretRequest,
    InterpretResponse,
)


settings = get_settings()
store = CreditStore(settings) if settings.database_url else None


@asynccontextmanager
async def lifespan(_: FastAPI):
    errors = settings.runtime_errors()
    if settings.app_env == "production" and errors:
        raise RuntimeError("Missing production configuration: " + ", ".join(errors))
    if store:
        await store.open()
    yield
    if store:
        await store.close()


app = FastAPI(
    title="Jale API",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.enable_api_docs else None,
    redoc_url="/redoc" if settings.enable_api_docs else None,
    openapi_url="/openapi.json" if settings.enable_api_docs else None,
)


def require_store() -> CreditStore:
    if store is None:
        raise HTTPException(status_code=503, detail="DATABASE_NOT_CONFIGURED")
    return store


def verify_origin(x_origin_verify: str | None = Header(default=None)) -> None:
    if settings.require_origin_verify and (
        not settings.origin_verify_secret
        or not hmac.compare_digest(x_origin_verify or "", settings.origin_verify_secret)
    ):
        raise HTTPException(status_code=403, detail="ORIGIN_DENIED")


async def optional_account(
    authorization: str | None = Header(default=None),
    credit_store: CreditStore = Depends(require_store),
) -> Account | None:
    token = bearer_value(authorization)
    if token is None:
        return None
    account = await credit_store.account_for_access_token(token)
    if account is None:
        raise HTTPException(status_code=401, detail="AUTH_INVALID")
    return account


async def required_account(
    account: Account | None = Depends(optional_account),
) -> Account:
    if account is None:
        raise HTTPException(status_code=401, detail="EMAIL_REQUIRED")
    return account


def installation_key(credit_store: CreditStore, installation_id: str) -> str:
    if len(installation_id) < 20 or len(installation_id) > 128:
        raise HTTPException(status_code=400, detail="INSTALLATION_ID_INVALID")
    return credit_store.installation_hash(installation_id)


@app.get("/health")
async def health():
    errors = settings.runtime_errors()
    ready = bool(store) and not errors and await store.ready()
    payload = {
        "status": "ok" if ready else "unavailable",
        "database": "ready" if ready else "unavailable",
        "backend": settings.ai_backend,
    }
    return JSONResponse(payload, status_code=200 if ready else 503)


@app.post(
    "/internal/auth/codes",
    response_model=AuthCodeResponse,
    include_in_schema=False,
)
async def create_auth_code(
    payload: AuthCodeRequest,
    x_auth_bridge: str | None = Header(default=None),
    credit_store: CreditStore = Depends(require_store),
):
    if (
        len(settings.auth_bridge_secret) < 32
        or not hmac.compare_digest(x_auth_bridge or "", settings.auth_bridge_secret)
    ):
        raise HTTPException(status_code=403, detail="AUTH_BRIDGE_DENIED")
    code = await credit_store.issue_auth_code(
        account=Account(payload.user_id, payload.email),
        code_challenge=payload.code_challenge,
        redirect_uri=payload.redirect_uri,
    )
    return AuthCodeResponse(code=code)


@app.post(
    "/v1/auth/exchange",
    response_model=AuthSessionResponse,
    dependencies=[Depends(verify_origin)],
)
async def exchange_auth_code(
    payload: AuthExchangeRequest,
    credit_store: CreditStore = Depends(require_store),
):
    session = await credit_store.exchange_auth_code(
        code=payload.code,
        verifier=payload.code_verifier,
        redirect_uri=payload.redirect_uri,
    )
    if session is None:
        raise HTTPException(status_code=401, detail="AUTH_CODE_INVALID")
    return session


@app.post(
    "/v1/auth/refresh",
    response_model=AuthSessionResponse,
    dependencies=[Depends(verify_origin)],
)
async def refresh_auth(
    payload: AuthRefreshRequest,
    credit_store: CreditStore = Depends(require_store),
):
    session = await credit_store.refresh_session(payload.refresh_token)
    if session is None:
        raise HTTPException(status_code=401, detail="AUTH_INVALID")
    return session


@app.post("/v1/auth/logout", dependencies=[Depends(verify_origin)])
async def logout(
    payload: AuthLogoutRequest,
    credit_store: CreditStore = Depends(require_store),
):
    await credit_store.revoke_session(payload.refresh_token)
    return {"ok": True}


@app.get(
    "/v1/account",
    response_model=CreditState,
    dependencies=[Depends(verify_origin)],
)
async def account_state(
    installation_id: str = Header(alias="X-Installation-ID"),
    account: Account | None = Depends(optional_account),
    credit_store: CreditStore = Depends(require_store),
):
    key = installation_key(credit_store, installation_id)
    return await credit_store.state(account, key)


@app.post(
    "/v1/quotes/interpret",
    response_model=InterpretResponse,
    dependencies=[Depends(verify_origin)],
)
async def interpret(
    payload: InterpretRequest,
    request: Request,
    idempotency_key: UUID = Header(alias="Idempotency-Key"),
    installation_id: str = Header(alias="X-Installation-ID"),
    account: Account | None = Depends(optional_account),
    credit_store: CreditStore = Depends(require_store),
):
    await verify_app_integrity(request, settings)
    if settings.ai_backend == "gateway":
        if not settings.ai_gateway_url or len(settings.ai_gateway_token) < 32:
            raise HTTPException(status_code=503, detail="AI_GATEWAY_NOT_CONFIGURED")
    elif not settings.openai_api_key:
        raise HTTPException(status_code=503, detail="OPENAI_NOT_CONFIGURED")
    if payload.installation_id != installation_id or payload.request_id != idempotency_key:
        raise HTTPException(status_code=403, detail="REQUEST_CONTEXT_MISMATCH")
    key = installation_key(credit_store, installation_id)
    request_hash = hashlib.sha256(payload.model_dump_json().encode()).hexdigest()
    try:
        reservation = await credit_store.reserve(
            account=account,
            installation_hash=key,
            idempotency_key=idempotency_key,
            request_hash=request_hash,
            model=settings.openai_model if settings.ai_backend == "openai" else "gateway",
        )
    except CreditUnavailable as error:
        status = {
            "EMAIL_REQUIRED": 401,
            "REQUEST_IN_PROGRESS": 409,
            "IDEMPOTENCY_REUSED": 409,
        }.get(error.code, 429)
        raise HTTPException(status_code=status, detail=error.code) from error
    try:
        quote, usage = await interpret_quote(settings, payload, key)
        response = InterpretResponse(
            quote=quote,
            credits=await credit_store.state(account, key),
            model=settings.openai_model if settings.ai_backend == "openai" else "gateway",
        )
        await credit_store.finish(
            reservation,
            input_tokens=getattr(usage, "input_tokens", 0) if usage else 0,
            output_tokens=getattr(usage, "output_tokens", 0) if usage else 0,
        )
        return response
    except AiProviderError as error:
        await credit_store.cancel(reservation)
        if error.code in {"RATE_LIMIT", "QUOTA_EXCEEDED"}:
            raise HTTPException(status_code=429, detail="RATE_LIMITED") from error
        raise HTTPException(status_code=502, detail="AI_UNAVAILABLE") from error
    except Exception:
        await credit_store.cancel(reservation)
        raise HTTPException(status_code=502, detail="AI_UNAVAILABLE")


@app.get(
    "/v1/billing/plans",
    response_model=list[BillingPlan],
    dependencies=[Depends(verify_origin)],
)
async def billing_plans():
    try:
        return await list_plans(settings)
    except Exception as error:
        raise HTTPException(status_code=503, detail="STRIPE_NOT_CONFIGURED") from error


@app.post(
    "/v1/billing/checkout",
    response_model=BillingSessionResponse,
    dependencies=[Depends(verify_origin)],
)
async def create_checkout(
    payload: CheckoutRequest,
    account: Account = Depends(required_account),
    credit_store: CreditStore = Depends(require_store),
):
    try:
        return BillingSessionResponse(
            url=await checkout_url(settings, credit_store, account, payload.plan)
        )
    except Exception as error:
        raise HTTPException(status_code=503, detail="STRIPE_UNAVAILABLE") from error


@app.post(
    "/v1/billing/portal",
    response_model=BillingSessionResponse,
    dependencies=[Depends(verify_origin)],
)
async def create_portal(
    account: Account = Depends(required_account),
    credit_store: CreditStore = Depends(require_store),
):
    try:
        return BillingSessionResponse(
            url=await portal_url(settings, credit_store, account)
        )
    except Exception as error:
        raise HTTPException(status_code=503, detail="STRIPE_UNAVAILABLE") from error


@app.post("/v1/billing/stripe/webhook", include_in_schema=False)
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(alias="Stripe-Signature"),
    credit_store: CreditStore = Depends(require_store),
):
    body = await request.body()
    try:
        event = parse_webhook(settings, body, stripe_signature)
    except Exception as error:
        raise HTTPException(status_code=400, detail="STRIPE_SIGNATURE_INVALID") from error
    customer, subscription, active, pro_until = subscription_change(event)
    await credit_store.apply_stripe_event(
        event_id=event["id"],
        event_type=event["type"],
        payload=event,
        customer_id=customer,
        subscription_id=subscription,
        active=active,
        pro_until=pro_until,
    )
    return {"received": True}
