"""
config/config.py — Application configuration classes
Supports development, testing, and production environments.
"""

import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()


class Config:
    """Base configuration shared by all environments."""

    # ── Flask ─────────────────────────────────────────────────
    SECRET_KEY: str = os.getenv("SECRET_KEY", "dev-secret-key-change-in-prod")
    DEBUG: bool = False
    TESTING: bool = False

    # ── Database ──────────────────────────────────────────────
    SQLALCHEMY_DATABASE_URI: str = os.getenv(
        "DATABASE_URL",
        "postgresql://attendease_user:StrongPass%402024@localhost:5432/attendease",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS: bool = False
    SQLALCHEMY_ENGINE_OPTIONS: dict = {
        "pool_size": 10,
        "pool_recycle": 300,
        "pool_pre_ping": True,
        "max_overflow": 20,
    }

    # ── JWT ───────────────────────────────────────────────────
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "jwt-secret-change-me")
    JWT_REFRESH_SECRET: str = os.getenv("JWT_REFRESH_SECRET", "refresh-secret-change-me")
    JWT_ACCESS_EXPIRES: timedelta = timedelta(
        minutes=int(os.getenv("JWT_ACCESS_EXPIRES_MINUTES", 15))
    )
    JWT_REFRESH_EXPIRES: timedelta = timedelta(
        days=int(os.getenv("JWT_REFRESH_EXPIRES_DAYS", 7))
    )

    # ── CORS ──────────────────────────────────────────────────
    CORS_ORIGINS: list = os.getenv(
        "CORS_ORIGINS", "http://localhost:3000,http://localhost:8080"
    ).split(",")

    # ── File Upload ───────────────────────────────────────────
    UPLOAD_FOLDER: str = os.getenv("UPLOAD_FOLDER", "uploads")
    MAX_CONTENT_LENGTH: int = int(os.getenv("MAX_CONTENT_LENGTH", 16 * 1024 * 1024))
    ALLOWED_EXTENSIONS: set = set(
        os.getenv("ALLOWED_EXTENSIONS", "jpg,jpeg,png,webp").split(",")
    )

    # ── Redis ─────────────────────────────────────────────────
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    RATELIMIT_STORAGE_URI: str = os.getenv("RATELIMIT_STORAGE_URI", os.getenv("REDIS_URL", "memory://"))


    # ── Email ─────────────────────────────────────────────────
    MAIL_SERVER: str = os.getenv("MAIL_SERVER", "smtp.gmail.com")
    MAIL_PORT: int = int(os.getenv("MAIL_PORT", 587))
    MAIL_USE_TLS: bool = os.getenv("MAIL_USE_TLS", "true").lower() == "true"
    MAIL_USERNAME: str = os.getenv("MAIL_USERNAME", "")
    MAIL_PASSWORD: str = os.getenv("MAIL_PASSWORD", "")
    MAIL_DEFAULT_SENDER: str = os.getenv(
        "MAIL_DEFAULT_SENDER", "AttendEase <noreply@attendease.com>"
    )

    # ── App ───────────────────────────────────────────────────
    APP_NAME: str = os.getenv("APP_NAME", "AttendEase")
    FRONTEND_URL: str = os.getenv("FRONTEND_URL", "http://localhost:3000")

    # ── Logging ───────────────────────────────────────────────
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_FILE: str = os.getenv("LOG_FILE", "logs/app.log")

    # Shift defaults (overridden per employee)
    DEFAULT_SHIFT_START: str = "08:00"
    DEFAULT_SHIFT_END: str = "17:00"
    DEFAULT_LATE_THRESHOLD_MINUTES: int = 15


class DevelopmentConfig(Config):
    DEBUG = True
    LOG_LEVEL = "DEBUG"


class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "postgresql://attendease_user:test@localhost:5432/attendease_test"
    JWT_ACCESS_EXPIRES = timedelta(minutes=5)
    RATELIMIT_ENABLED = False


class ProductionConfig(Config):
    DEBUG = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        **Config.SQLALCHEMY_ENGINE_OPTIONS,
        "pool_size": 20,
        "max_overflow": 40,
    }


# Environment map
config_map: dict = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}

# Active config based on FLASK_ENV
active_config = config_map.get(
    os.getenv("FLASK_ENV", "development"), DevelopmentConfig
)
