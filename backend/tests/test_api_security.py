from fastapi.testclient import TestClient

from app.main import app


def test_sensitive_routes_require_origin_secret():
    client = TestClient(app)
    response = client.get(
        "/v1/account",
        headers={"X-Installation-ID": "installation-id-that-is-long-enough"},
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "ORIGIN_DENIED"


def test_api_docs_are_disabled_by_default():
    client = TestClient(app)
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404
