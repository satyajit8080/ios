from functools import lru_cache
from typing import List
 
from pydantic_settings import BaseSettings, SettingsConfigDict
 
 
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
 
    PROJECT_NAME: str = "AI Weight Loss Coach"
    API_V1: str = "/api/v1"
    ENVIRONMENT: str = "development"
    SECRET_KEY: str = "dev-secret-change-me"
 
    DATABASE_URL: str = "postgresql+psycopg://awlc:awlc@db:5432/awlc"
    REDIS_URL: str = "redis://redis:6379/0"
 
    ACCESS_TOKEN_MINUTES: int = 30
    REFRESH_TOKEN_DAYS: int = 60
    RESET_TOKEN_MINUTES: int = 30
 
    OPENAI_API_KEY: str = ""
    # Any OpenAI-compatible endpoint works here (OpenRouter, Together, a local
    # server). Leave empty to talk to OpenAI directly.
    OPENAI_BASE_URL: str = ""
    ANTHROPIC_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-4o"
    OPENAI_VISION_MODEL: str = "gpt-4o"
    ANTHROPIC_MODEL: str = "claude-sonnet-4-5"
    AI_PRIMARY: str = "openai"
 
    APPLE_BUNDLE_ID: str = "com.awlc.coach"
    APPLE_TEAM_ID: str = ""
    APPLE_KEYS_URL: str = "https://appleid.apple.com/auth/keys"
    APPLE_ISSUER: str = "https://appleid.apple.com"
 
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""
 
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = "coach@awlc.app"
    FRONTEND_RESET_URL: str = "https://awlc.app/reset"
 
    CORS_ORIGINS: List[str] = ["*"]
 
    # Nutrition safety floors (kcal/day). Never generate targets below these.
    MIN_CALORIES_FEMALE: int = 1200
    MIN_CALORIES_MALE: int = 1500
    MAX_WEEKLY_LOSS_KG: float = 1.0
 
    PREMIUM_PRODUCTS: List[str] = ["com.awlc.coach.premium.monthly", "com.awlc.coach.premium.annual"]
 
 
@lru_cache
def get_settings() -> Settings:
    return Settings()
 
 
settings = get_settings()
