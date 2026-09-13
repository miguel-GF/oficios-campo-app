from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: Literal["development", "test", "production"] = "development"
    openai_api_key: str = ""
    openai_model: str = "gpt-5.6-luna"
    ai_backend: Literal["gateway", "openai"] = "gateway"
    ai_gateway_url: str = ""
    ai_gateway_token: str = ""
    ai_gateway_timeout_seconds: float = Field(default=25.0, ge=5.0, le=60.0)
    database_url: str = ""
    installation_pepper: str = ""
    origin_verify_secret: str = ""
    auth_bridge_secret: str = ""
    auth_portal_url: str = ""
    require_origin_verify: bool = True
    require_app_integrity: bool = True
    enable_api_docs: bool = False
    pro_fair_use_monthly: int = Field(default=500, ge=50, le=5000)
    direct_android_package: str = "mx.jale.app"
    play_android_package: str = "mx.jale.app.play"
    direct_certificate_sha256: str = ""
    play_certificate_sha256: str = ""
    google_cloud_project_number: str = ""
    google_service_account_json: str = ""
    direct_version_codes: str = "1"
    play_version_codes: str = "1"
    stripe_secret_key: str = ""
    stripe_webhook_secret: str = ""
    stripe_monthly_price_id: str = ""
    stripe_yearly_price_id: str = ""
    stripe_success_url: str = "https://jale.mx/pro/ok"
    stripe_cancel_url: str = "https://jale.mx/pro/cancelado"
    stripe_portal_return_url: str = "https://jale.mx/pro"

    def runtime_errors(self) -> list[str]:
        errors: list[str] = []
        if not self.database_url:
            errors.append("DATABASE_URL")
        if len(self.installation_pepper) < 32:
            errors.append("INSTALLATION_PEPPER")
        if self.require_origin_verify and len(self.origin_verify_secret) < 32:
            errors.append("ORIGIN_VERIFY_SECRET")
        if self.app_env == "production":
            if len(self.auth_bridge_secret) < 32:
                errors.append("AUTH_BRIDGE_SECRET")
            if not self.auth_portal_url.startswith("https://"):
                errors.append("AUTH_PORTAL_URL")
            if self.ai_backend == "gateway" and (
                not self.ai_gateway_url.startswith("https://")
                or len(self.ai_gateway_token) < 32
            ):
                errors.append("AI_GATEWAY")
            if self.ai_backend != "gateway":
                errors.append("AI_BACKEND_MUST_BE_GATEWAY")
            if not self.stripe_secret_key or not self.stripe_webhook_secret:
                errors.append("STRIPE_SECRETS")
            if not self.stripe_monthly_price_id or not self.stripe_yearly_price_id:
                errors.append("STRIPE_PRICE_IDS")
        return errors


@lru_cache
def get_settings() -> Settings:
    return Settings()
