"""
middleware/rate_limiter.py — Flask-Limiter with Redis backend
"""

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200 per minute", "2000 per hour"],
    storage_uri=None,           # Set from app.config["RATELIMIT_STORAGE_URI"] at init
    strategy="fixed-window",
)
