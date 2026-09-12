from typing import Any

import httpx
from openai import AsyncOpenAI
from pydantic import ValidationError

from .config import Settings
from .models import InterpretRequest, QuoteDraft


class AiProviderError(RuntimeError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


SYSTEM_PROMPT = """Eres el capturista de cotizaciones de Jale para trabajadores de oficio en México.
Extrae únicamente lo que la persona dijo. Divide el trabajo en conceptos claros, cantidades y precios.
Los precios son pesos mexicanos y unit_price_cents siempre son centavos. Si no se dijo un precio usa 0;
nunca inventes uno. No incluyas IVA salvo que se mencione. Conserva detalles útiles en notas.
Corrige errores obvios de transcripción sin cambiar el sentido."""


async def _interpret_openai(settings: Settings, request: InterpretRequest):
    client = AsyncOpenAI(
        api_key=settings.openai_api_key,
        timeout=20.0,
        max_retries=0,
    )
    context = f"Oficio: {request.trade or 'no indicado'}."
    if request.client_hint:
        context += f" Posible cliente: {request.client_hint}."
    response = await client.responses.parse(
        model=settings.openai_model,
        reasoning={"effort": "low"},
        max_output_tokens=800,
        store=False,
        input=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"{context}\nDictado: {request.transcript}"},
        ],
        text_format=QuoteDraft,
    )
    if response.output_parsed is None:
        raise RuntimeError("MODEL_OUTPUT_INVALID")
    return response.output_parsed, response.usage


def _gateway_text(request: InterpretRequest) -> str:
    context = f"Oficio: {request.trade or 'no indicado'}."
    if request.client_hint:
        context += f" Posible cliente: {request.client_hint}."
    text = f"{context}\nDictado: {request.transcript}"
    # The central feature accepts 2,000 characters. Preserve the complete
    # transcript at that boundary and drop only optional context if needed.
    return text if len(text) <= 2_000 else request.transcript


async def _gateway_request(
    settings: Settings,
    request: InterpretRequest,
    subject_id: str,
    client: httpx.AsyncClient,
) -> tuple[QuoteDraft, None]:
    response = await client.post(
        f"{settings.ai_gateway_url.rstrip('/')}/internal/oficios/interpret",
        headers={
            "Authorization": f"Bearer {settings.ai_gateway_token}",
            "Content-Type": "application/json",
            "Idempotency-Key": str(request.request_id),
        },
        json={"subject_id": subject_id, "text": _gateway_text(request)},
    )
    try:
        payload: Any = response.json()
    except ValueError as error:
        raise AiProviderError("AI_INVALID_RESPONSE") from error
    if not isinstance(payload, dict):
        raise AiProviderError("AI_INVALID_RESPONSE")
    if response.status_code < 200 or response.status_code >= 300 or payload.get("success") is not True:
        error = payload.get("error")
        code = error.get("code") if isinstance(error, dict) else None
        raise AiProviderError(code if isinstance(code, str) else "AI_UNAVAILABLE")
    if payload.get("request_id") != str(request.request_id) or payload.get("feature") != "interpret_quote":
        raise AiProviderError("AI_INVALID_RESPONSE")
    data = payload.get("data")
    try:
        return QuoteDraft.model_validate(data), None
    except (TypeError, ValidationError) as error:
        raise AiProviderError("AI_INVALID_RESPONSE") from error


async def _interpret_gateway(
    settings: Settings,
    request: InterpretRequest,
    subject_id: str,
):
    try:
        async with httpx.AsyncClient(timeout=settings.ai_gateway_timeout_seconds) as client:
            return await _gateway_request(settings, request, subject_id, client)
    except AiProviderError:
        raise
    except (httpx.HTTPError, TimeoutError) as error:
        raise AiProviderError("AI_UNAVAILABLE") from error


async def interpret_quote(
    settings: Settings,
    request: InterpretRequest,
    subject_id: str,
):
    if settings.ai_backend == "gateway":
        return await _interpret_gateway(settings, request, subject_id)
    return await _interpret_openai(settings, request)
