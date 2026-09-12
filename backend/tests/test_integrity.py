from app.integrity import request_hash
from app.models import InterpretRequest
from fastapi import HTTPException
import pytest
from app.main import verify_origin
from pydantic import ValidationError


def test_request_hash_is_stable_and_url_safe():
    value = request_hash(b'{"transcript":"instala dos contactos"}')
    assert value == "a1B3iEBIeOmC4HcIht7mV5Xgom_Q6uQwCC7bqYMz0ak"
    assert "=" not in value


def test_empty_origin_secret_never_allows_direct_access():
    with pytest.raises(HTTPException) as caught:
        verify_origin(None)
    assert caught.value.status_code == 403


def test_interpret_request_binds_installation_and_request_id():
    payload = InterpretRequest(
        transcript="instala dos contactos",
        trade="electricista",
        installation_id="installation-id-that-is-long-enough",
        request_id="3f0f6f00-1f32-4f2e-8a5a-2c0f1c2c4d90",
    )
    assert payload.installation_id.startswith("installation-")
    assert str(payload.request_id) == "3f0f6f00-1f32-4f2e-8a5a-2c0f1c2c4d90"
    with pytest.raises(ValidationError):
        InterpretRequest(
            transcript="instala dos contactos",
            installation_id="corto",
            request_id="3f0f6f00-1f32-4f2e-8a5a-2c0f1c2c4d90",
        )
