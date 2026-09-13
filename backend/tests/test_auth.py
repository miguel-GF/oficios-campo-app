import pytest
from fastapi import HTTPException

from app.auth import bearer_value


def test_bearer_token_is_parsed_without_decoding_client_side_claims():
    assert bearer_value("Bearer opaque-mobile-token") == "opaque-mobile-token"
    assert bearer_value(None) is None


def test_malformed_bearer_token_is_rejected():
    with pytest.raises(HTTPException) as caught:
        bearer_value("Basic token")
    assert caught.value.status_code == 401
