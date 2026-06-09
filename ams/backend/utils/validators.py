"""
utils/validators.py — Common input validators
"""

import re
from typing import Optional


def validate_password_strength(password: str) -> Optional[str]:
    """
    Enforce: min 8 chars, 1 uppercase, 1 digit, 1 special char.
    Returns error message or None.
    """
    if len(password) < 8:
        return "Password must be at least 8 characters"
    if not re.search(r"[A-Z]", password):
        return "Password must contain at least one uppercase letter"
    if not re.search(r"\d", password):
        return "Password must contain at least one digit"
    if not re.search(r"[!@#$%^&*(),.?\":{}|<>]", password):
        return "Password must contain at least one special character"
    return None


def validate_phone(phone: str) -> bool:
    """Basic E.164 and local phone number validation."""
    cleaned = re.sub(r"[\s\-\(\)]", "", phone)
    return bool(re.match(r"^\+?[1-9]\d{7,14}$", cleaned))


def validate_employee_id_format(eid: str) -> bool:
    """EMP-YYYY-NNNN format."""
    return bool(re.match(r"^(EMP|ADM)-\d{4}-\d{4}$", eid))


def sanitize_string(s: str, max_len: int = 500) -> str:
    """Strip whitespace and truncate."""
    return s.strip()[:max_len] if s else ""
