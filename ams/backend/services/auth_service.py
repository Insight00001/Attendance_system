"""
services/auth_service.py — Authentication business logic
Handles login, register, token refresh, password reset.
"""

import bcrypt
import secrets
from datetime import datetime, timezone, timedelta
from typing import Optional, Tuple

from config.database import db
from models import User, Employee, Session, Notification
from utils.jwt_handler import JWTHandler
from utils.logger import get_logger

logger = get_logger(__name__)


class AuthService:
    """Handles all authentication operations."""

    # Max failed attempts before lockout
    MAX_FAILED_ATTEMPTS = 5
    LOCKOUT_MINUTES = 30

    # ── Password Hashing ─────────────────────────────────────

    @staticmethod
    def hash_password(plain: str) -> str:
        """Hash a password with bcrypt (cost=12)."""
        salt = bcrypt.gensalt(rounds=12)
        return bcrypt.hashpw(plain.encode("utf-8"), salt).decode("utf-8")

    @staticmethod
    def verify_password(plain: str, hashed: str) -> bool:
        """Verify a plaintext password against its bcrypt hash."""
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))

    # ── Login ─────────────────────────────────────────────────

    @classmethod
    def login(
        cls,
        email: str,
        password: str,
        device_info: Optional[dict] = None,
    ) -> Tuple[Optional[dict], Optional[str]]:
        """
        Authenticate user by email + password.

        Returns:
            (token_bundle, error_message)
            token_bundle = { access_token, refresh_token, user, employee }
        """
        user = User.query.filter_by(email=email.lower().strip()).first()

        # Generic error to prevent user enumeration
        NOT_FOUND_MSG = "Invalid email or password"

        if not user:
            logger.warning(f"Login attempt for unknown email: {email}")
            return None, NOT_FOUND_MSG

        if not user.is_active:
            return None, "Account is deactivated. Contact admin."

        # Check lockout
        if user.is_locked():
            remaining = int((user.locked_until - datetime.now(timezone.utc)).total_seconds() / 60)
            return None, f"Account locked. Try again in {remaining} minutes."

        # Verify password
        if not cls.verify_password(password, user.password_hash):
            user.failed_attempts += 1
            if user.failed_attempts >= cls.MAX_FAILED_ATTEMPTS:
                user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=cls.LOCKOUT_MINUTES)
                logger.warning(f"Account locked: {email} after {cls.MAX_FAILED_ATTEMPTS} attempts")
            db.session.commit()
            return None, NOT_FOUND_MSG

        # Successful login — reset counters
        user.failed_attempts = 0
        user.locked_until = None
        user.last_login_at = datetime.now(timezone.utc)

        # Create tokens
        access_token  = JWTHandler.create_access_token(str(user.id), user.email, user.user_role)
        refresh_token = JWTHandler.create_refresh_token(str(user.id))

        # Persist refresh token as a session
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)
        session = Session(
            user_id=user.id,
            refresh_token=refresh_token,
            device_info=device_info,
            expires_at=expires_at,
        )
        db.session.add(session)
        db.session.commit()

        logger.info(f"Login successful: {email} ({user.user_role})")

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": 900,   # 15 minutes in seconds
            "user": user.to_dict(),
            "employee": user.employee.to_dict() if user.employee else None,
        }, None

    # ── Refresh Token ─────────────────────────────────────────

    @classmethod
    def refresh_tokens(cls, refresh_token: str) -> Tuple[Optional[dict], Optional[str]]:
        """Exchange a valid refresh token for new token pair."""
        payload = JWTHandler.decode_refresh_token(refresh_token)
        if not payload:
            return None, "Invalid or expired refresh token"

        # Check session is valid and not revoked
        session = Session.query.filter_by(
            refresh_token=refresh_token,
            is_revoked=False,
        ).first()

        if not session or session.expires_at < datetime.now(timezone.utc):
            return None, "Session expired. Please login again."

        user = User.query.filter_by(id=payload["sub"], is_active=True).first()
        if not user:
            return None, "User not found"

        # Rotate tokens (revoke old, create new)
        session.is_revoked = True

        new_access  = JWTHandler.create_access_token(str(user.id), user.email, user.user_role)
        new_refresh = JWTHandler.create_refresh_token(str(user.id))

        new_session = Session(
            user_id=user.id,
            refresh_token=new_refresh,
            device_info=session.device_info,
            expires_at=datetime.now(timezone.utc) + timedelta(days=7),
        )
        db.session.add(new_session)
        db.session.commit()

        return {"access_token": new_access, "refresh_token": new_refresh, "expires_in": 900}, None

    # ── Logout ────────────────────────────────────────────────

    @staticmethod
    def logout(refresh_token: str) -> bool:
        """Revoke a refresh token session."""
        session = Session.query.filter_by(refresh_token=refresh_token).first()
        if session:
            session.is_revoked = True
            db.session.commit()
            return True
        return False

    # ── Admin Create ──────────────────────────────────────────

    @classmethod
    def create_admin(cls, email: str, password: str, name: str, role: str = "admin") -> User:
        """Utility to create an admin user (used by setup scripts)."""
        existing = User.query.filter_by(email=email.lower()).first()
        if existing:
            raise ValueError(f"User {email} already exists")

        user = User(
            email=email.lower().strip(),
            password_hash=cls.hash_password(password),
            user_role=role,
            is_active=True,
            is_verified=True,
        )
        db.session.add(user)
        db.session.flush()  # Get user.id before commit

        # Create a minimal employee record for admin
        first, *rest = name.split()
        last = " ".join(rest) if rest else "Admin"
        employee = Employee(
            user_id=user.id,
            employee_id=f"ADM-{secrets.token_hex(3).upper()}",
            first_name=first,
            last_name=last,
            employment_status="active",
        )
        db.session.add(employee)
        db.session.commit()
        logger.info(f"Admin created: {email}")
        return user

    # ── Password Reset ────────────────────────────────────────

    @classmethod
    def initiate_password_reset(cls, email: str) -> Tuple[Optional[str], Optional[str]]:
        """Generate a password reset token and return it (caller sends email)."""
        user = User.query.filter_by(email=email.lower()).first()
        if not user:
            # Return success to prevent enumeration
            return "OK", None

        token = JWTHandler.create_reset_token(str(user.id))
        user.reset_token = token
        user.reset_token_expires = datetime.now(timezone.utc) + timedelta(minutes=30)
        db.session.commit()
        return token, None

    @classmethod
    def complete_password_reset(cls, token: str, new_password: str) -> Tuple[bool, Optional[str]]:
        """Validate reset token and set new password."""
        payload = JWTHandler.decode_reset_token(token)
        if not payload:
            return False, "Reset token is invalid or expired"

        user = User.query.filter_by(id=payload["sub"], reset_token=token).first()
        if not user:
            return False, "Invalid reset token"

        user.password_hash = cls.hash_password(new_password)
        user.reset_token = None
        user.reset_token_expires = None
        user.failed_attempts = 0
        user.locked_until = None
        db.session.commit()
        return True, None
