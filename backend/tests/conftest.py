"""
tests/conftest.py — Shared pytest fixtures
"""

import pytest
import os

# Point to test DB before any app import
os.environ.setdefault("DATABASE_URL",
    "postgresql://attendease_user:test@localhost:5432/attendease_test")
os.environ.setdefault("FLASK_ENV", "testing")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-32chars-here")
os.environ.setdefault("JWT_REFRESH_SECRET", "test-refresh-secret-32chars-here")
os.environ.setdefault("RATELIMIT_ENABLED", "false")
