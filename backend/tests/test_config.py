from app.config import Settings


def test_production_configuration_fails_closed_without_services():
    errors = Settings(app_env="production").runtime_errors()
    assert "DATABASE_URL" in errors
    assert "AUTH_BRIDGE_SECRET" in errors
    assert "STRIPE_SECRETS" in errors
    assert "AI_GATEWAY" in errors


def test_development_allows_unconfigured_external_services():
    settings = Settings(app_env="development", require_origin_verify=False)
    assert settings.runtime_errors() == ["DATABASE_URL", "INSTALLATION_PEPPER"]
