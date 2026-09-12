import math

from pydantic import BaseModel, Field, field_validator
from uuid import UUID


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
    manual_remaining: int
    signup_bonus_remaining: int
    period: str


class InterpretResponse(BaseModel):
    quote: QuoteDraft
    credits: CreditState
    model: str


class VerifyPurchaseRequest(BaseModel):
    purchase_token: str = Field(min_length=20, max_length=4096)
    product_id: str = Field(min_length=2, max_length=100)


class VerifyPurchaseResponse(BaseModel):
    active: bool
    expires_at: str | None
    base_plan_id: str | None
