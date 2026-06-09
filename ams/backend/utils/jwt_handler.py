"""
utils/jwt_handler.py — JWT access and refresh token management
"""

import jwt
import uuid
from datetime import datetime, timezone
from typing import Optional
from flask import current_app


class JWTHandler:
    """
    Handles creation and verification of access + refresh tokens.

    Access token payload:
        { sub, email, role, exp, iat, jti }

    Refresh token payload:
        { sub, type: 'refresh', exp, iat, jti }
    """

    @staticmethod
    def create_access_token(user_id: str, email: str, role: str) -> str:
        """Create short-lived JWT access token (15 min)."""
        payload = {
            "sub": user_id,
            "email": email,
            "role": role,
            "type": "access",
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + current_app.config["JWT_ACCESS_EXPIRES"],
            "jti": str(uuid.uuid4()),
        }
        return jwt.encode(
            payload,
            current_app.config["JWT_SECRET_KEY"],
            algorithm="HS256",
        )

    @staticmethod
    def create_refresh_token(user_id: str) -> str:
        """Create long-lived JWT refresh token (7 days)."""
        payload = {
            "sub": user_id,
            "type": "refresh",
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + current_app.config["JWT_REFRESH_EXPIRES"],
            "jti": str(uuid.uuid4()),
        }
        return jwt.encode(
            payload,
            current_app.config["JWT_REFRESH_SECRET"],
            algorithm="HS256",
        )

    @staticmethod
    def decode_access_token(token: str) -> Optional[dict]:
        """
        Decode and validate an access token.
        Returns payload dict or None on failure.
        """
        try:
            payload = jwt.decode(
                token,
                current_app.config["JWT_SECRET_KEY"],
                algorithms=["HS256"],
            )
            if payload.get("type") != "access":
                return None
            return payload
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

    @staticmethod
    def decode_refresh_token(token: str) -> Optional[dict]:
        """
        Decode and validate a refresh token.
        Returns payload dict or None on failure.
        """
        try:
            payload = jwt.decode(
                token,
                current_app.config["JWT_REFRESH_SECRET"],
                algorithms=["HS256"],
            )
            if payload.get("type") != "refresh":
                return None
            return payload
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

    @staticmethod
    def create_reset_token(user_id: str) -> str:
        """Short-lived token for password reset (30 min)."""
        from datetime import timedelta
        payload = {
            "sub": user_id,
            "type": "reset",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=30),
            "jti": str(uuid.uuid4()),
        }
        return jwt.encode(
            payload,
            current_app.config["JWT_SECRET_KEY"],
            algorithm="HS256",
        )

    @staticmethod
    def decode_reset_token(token: str) -> Optional[dict]:
        try:
            payload = jwt.decode(
                token,
                current_app.config["JWT_SECRET_KEY"],
                algorithms=["HS256"],
            )
            if payload.get("type") != "reset":
                return None
            return payload
        except jwt.InvalidTokenError:
            return None
