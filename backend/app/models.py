import math
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class QuoteLineDraft(BaseModel):
    concept: str = Field(min_length=2, max_length=160)
    quantity: float = Field(gt=0, le=100_000)
    unit_price_cents: int = Field(ge=0, le=1_000_000_000)

    @field_validator("concept")
    @classmethod
    def clean_concept(cls, value: str) -> str:
        return " ".join(value.split())

    @field_validator("quantity")
    @classmethod
    def finite_quantity(cls, value: float) -> float:
        if not math.isfinite(value):
            raise ValueError("quantity must be finite")
        return value


class QuoteDraft(BaseModel):
    client_name: str = Field(default="", max_length=120)
    notes: str = Field(default="", max_length=500)
    lines: list[QuoteLineDraft] = Field(min_length=1, max_length=30)


class InterpretRequest(BaseModel):
    transcript: str = Field(min_length=4, max_length=2_000)
    trade: str = Field(default="", max_length=100)
    client_hint: str = Field(default="", max_length=120)
    installation_id: str = Field(min_length=20, max_length=128)
    request_id: UUID

    @field_validator("transcript")
    @classmethod
    def clean_transcript(cls, value: str) -> str:
        return " ".join(value.split())


class CreditState(BaseModel):
    authenticated: bool
    is_pro: bool
    ai_remaining: int | None
    period: str


class InterpretResponse(BaseModel):
    quote: QuoteDraft
    credits: CreditState
    model: str


class AuthCodeRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=255)
    email: str = Field(default="", max_length=320)
    code_challenge: str = Field(min_length=43, max_length=128)
    redirect_uri: str = Field(min_length=8, max_length=512)


class AuthCodeResponse(BaseModel):
    code: str
    expires_in: int = 300


class AuthExchangeRequest(BaseModel):
    code: str = Field(min_length=32, max_length=512)
    code_verifier: str = Field(min_length=43, max_length=128)
    redirect_uri: str = Field(min_length=8, max_length=512)


class AuthRefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=512)


class AuthLogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=512)


class AuthSessionResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int = 900
    user_id: str
    email: str


class BillingPlan(BaseModel):
    id: Literal["monthly", "yearly"]
    price_id: str
    unit_amount: int
    currency: str
    interval: str


class CheckoutRequest(BaseModel):
    plan: Literal["monthly", "yearly"]


class BillingSessionResponse(BaseModel):
    url: str
