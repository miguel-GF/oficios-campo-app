import hashlib
import hmac
from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request

from .ai import AiProviderError, interpret_quote
from .auth import Account, optional_account
from .billing import verify_google_subscription
from .config import get_settings
from .database import CreditStore, CreditUnavailable
from .integrity import verify_play_integrity
from .models import (
    CreditState,
    InterpretRequest,
    InterpretResponse,
    VerifyPurchaseRequest,
    VerifyPurchaseResponse,
)


settings = get_settings()
store = CreditStore(settings) if settings.database_url else None


@asynccontextmanager
async def lifespan(_: FastAPI):
    if store:
        store.open()
    yield
    if store:
        store.close()


app = FastAPI(
    title="Jale API",
    version="1.0.0",
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


def installation_key(
    request: Request,
    credit_store: CreditStore,
    installation_id: str,
) -> str:
    if len(installation_id) < 20 or len(installation_id) > 128:
        raise HTTPException(status_code=400, detail="INSTALLATION_ID_INVALID")
    return credit_store.installation_hash(installation_id)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "backend": settings.ai_backend,
        "model": settings.openai_model if settings.ai_backend == "openai" else "gateway",
    }


@app.get("/v1/account", response_model=CreditState, dependencies=[Depends(verify_origin)])
async def account_state(
    request: Request,
    installation_id: str = Header(alias="X-Installation-ID"),
    account: Account | None = Depends(optional_account),
    credit_store: CreditStore = Depends(require_store),
):
    key = installation_key(request, credit_store, installation_id)
    return credit_store.state(account, key)


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
    await verify_play_integrity(request, settings)
    if settings.ai_backend == "gateway":
        if not settings.ai_gateway_url or len(settings.ai_gateway_token) < 32:
            raise HTTPException(status_code=503, detail="AI_GATEWAY_NOT_CONFIGURED")
    elif not settings.openai_api_key:
        raise HTTPException(status_code=503, detail="OPENAI_NOT_CONFIGURED")
    if payload.installation_id != installation_id or payload.request_id != idempotency_key:
        raise HTTPException(status_code=403, detail="REQUEST_CONTEXT_MISMATCH")
    key = installation_key(request, credit_store, installation_id)
    request_hash = hashlib.sha256(payload.model_dump_json().encode()).hexdigest()
    try:
        reservation = credit_store.reserve(
            account=account,
            installation_hash=key,
            idempotency_key=idempotency_key,
            request_hash=request_hash,
            model=settings.openai_model if settings.ai_backend == "openai" else "gateway",
        )
    except CreditUnavailable as error:
        status = 401 if error.code == "EMAIL_REQUIRED" else 429
        raise HTTPException(status_code=status, detail=error.code) from error
    try:
        quote, usage = await interpret_quote(settings, payload, key)
        credit_store.finish(
            reservation,
            input_tokens=getattr(usage, "input_tokens", 0) if usage else 0,
            output_tokens=getattr(usage, "output_tokens", 0) if usage else 0,
        )
    except AiProviderError as error:
        credit_store.cancel(reservation)
        if error.code in {"RATE_LIMIT", "QUOTA_EXCEEDED"}:
            raise HTTPException(status_code=429, detail="RATE_LIMITED") from error
        raise HTTPException(status_code=502, detail="AI_UNAVAILABLE") from error
    except Exception:
        credit_store.cancel(reservation)
        raise HTTPException(status_code=502, detail="AI_UNAVAILABLE")
    return InterpretResponse(
        quote=quote,
        credits=credit_store.state(account, key),
        model=settings.openai_model if settings.ai_backend == "openai" else "gateway",
    )


@app.post(
    "/v1/billing/google-play/verify",
    response_model=VerifyPurchaseResponse,
    dependencies=[Depends(verify_origin)],
)
async def verify_purchase(
    payload: VerifyPurchaseRequest,
    request: Request,
    account: Account | None = Depends(optional_account),
    credit_store: CreditStore = Depends(require_store),
):
    await verify_play_integrity(request, settings)
    if account is None:
        raise HTTPException(status_code=401, detail="EMAIL_REQUIRED")
    if payload.product_id != settings.play_product_id:
        raise HTTPException(status_code=400, detail="PRODUCT_MISMATCH")
    try:
        active, expiry, base_plan, audit = await verify_google_subscription(
            settings, payload.purchase_token, account.user_id
        )
    except Exception as error:
        raise HTTPException(status_code=502, detail="PLAY_VERIFICATION_UNAVAILABLE") from error
    token_hash = hashlib.sha256(payload.purchase_token.encode()).hexdigest()
    credit_store.save_entitlement(
        account=account,
        token_hash=token_hash,
        active=active,
        expires_at=expiry,
        base_plan_id=base_plan,
        audit=audit,
    )
    return VerifyPurchaseResponse(
        active=active,
        expires_at=expiry.isoformat() if expiry else None,
        base_plan_id=base_plan,
    )
