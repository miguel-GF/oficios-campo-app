from functools import lru_cache

from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    openai_api_key: str = ""
    openai_model: str = "gpt-5.6-luna"
    ai_backend: Literal["gateway", "openai"] = "gateway"
    ai_gateway_url: str = ""
    ai_gateway_token: str = ""
    ai_gateway_timeout_seconds: float = Field(default=25.0, ge=5.0, le=60.0)
    database_url: str = ""
    supabase_url: str = ""
    supabase_anon_key: str = ""
    installation_pepper: str = Field(default="", min_length=0)
    origin_verify_secret: str = ""
    require_origin_verify: bool = True
    require_play_integrity: bool = True
    enable_api_docs: bool = False
    pro_fair_use_monthly: int = Field(default=500, ge=50, le=5000)
    google_play_service_account_json: str = ""
    android_package_name: str = "mx.jale.app"
    play_product_id: str = "jale_pro"


@lru_cache
def get_settings() -> Settings:
    return Settings()
