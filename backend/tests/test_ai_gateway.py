import asyncio
from uuid import UUID

import httpx
import pytest

from app.ai import AiProviderError, _gateway_request, _gateway_text, interpret_quote
from app.config import Settings
from app.models import InterpretRequest


REQUEST_ID = UUID("3f0f6f00-1f32-4f2e-8a5a-2c0f1c2c4d90")


def request() -> InterpretRequest:
    return InterpretRequest(
        transcript="instala dos contactos a 350 cada uno",
        trade="electricista",
        client_hint="Ana",
        installation_id="installation-id-that-is-long-enough",
        request_id=REQUEST_ID,
    )


class FakeClient:
    def __init__(self, response: httpx.Response):
        self.response = response
        self.url = None
        self.headers = None
        self.body = None

    async def post(self, url, *, headers, json):
        self.url = url
        self.headers = headers
        self.body = json
        return self.response


def settings() -> Settings:
    return Settings(
        ai_backend="gateway",
        ai_gateway_url="https://oficios-ai.example.workers.dev/",
        ai_gateway_token="t" * 32,
    )


def success_response() -> httpx.Response:
    return httpx.Response(
        200,
        json={
            "success": True,
            "request_id": str(REQUEST_ID),
            "feature": "interpret_quote",
            "data": {
                "client_name": "",
                "notes": "",
                "lines": [
                    {
                        "concept": "Instalar contacto",
                        "quantity": 2,
                        "unit_price_cents": 35000,
                    }
                ],
            },
            "meta": {"provider": "mock", "cached": False},
        },
    )


def test_gateway_adapter_contract_and_subject_hash_are_sent():
    client = FakeClient(success_response())

    quote, usage = asyncio.run(
        _gateway_request(settings(), request(), "a" * 64, client)
    )

    assert usage is None
    assert quote.lines[0].unit_price_cents == 35000
    assert client.url == "https://oficios-ai.example.workers.dev/internal/oficios/interpret"
    assert client.headers == {
        "Authorization": "Bearer " + "t" * 32,
        "Content-Type": "application/json",
        "Idempotency-Key": str(REQUEST_ID),
    }
    assert client.body == {
        "subject_id": "a" * 64,
        "text": "Oficio: electricista. Posible cliente: Ana.\n"
        "Dictado: instala dos contactos a 350 cada uno",
    }


def test_gateway_error_is_kept_as_provider_code():
    response = httpx.Response(
        429,
        json={
            "success": False,
            "request_id": str(REQUEST_ID),
            "error": {"code": "RATE_LIMIT", "message": "redacted"},
        },
    )

    with pytest.raises(AiProviderError) as caught:
        asyncio.run(_gateway_request(settings(), request(), "a" * 64, FakeClient(response)))

    assert caught.value.code == "RATE_LIMIT"


def test_gateway_backend_mode_does_not_use_direct_openai(monkeypatch):
    async def fake_gateway(settings, payload, subject_id):
        assert subject_id == "a" * 64
        return await _gateway_request(settings, payload, subject_id, FakeClient(success_response()))

    monkeypatch.setattr("app.ai._interpret_gateway", fake_gateway)
    quote, usage = asyncio.run(interpret_quote(settings(), request(), "a" * 64))

    assert usage is None
    assert quote.lines[0].concept == "Instalar contacto"


def test_full_transcript_keeps_all_text_when_optional_context_would_overflow():
    payload = request().model_copy(update={"transcript": "x" * 2_000})

    assert _gateway_text(payload) == "x" * 2_000


def test_malformed_gateway_data_is_rejected():
    response = httpx.Response(
        200,
        json={"success": True, "data": {"lines": []}},
    )

    with pytest.raises(AiProviderError) as caught:
        asyncio.run(_gateway_request(settings(), request(), "a" * 64, FakeClient(response)))

    assert caught.value.code == "AI_INVALID_RESPONSE"
