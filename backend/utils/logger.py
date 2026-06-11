"""
utils/logger.py — Structured logging setup
"""

import logging
import os
import sys
from logging.handlers import RotatingFileHandler


def setup_logger(app):
    """Configure app-level logging with file + console handlers."""
    log_level = getattr(logging, app.config.get("LOG_LEVEL", "INFO").upper(), logging.INFO)
    log_file = app.config.get("LOG_FILE", "logs/app.log")

    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    formatter = logging.Formatter(
        "[%(asctime)s] %(levelname)s in %(module)s (%(funcName)s:%(lineno)d): %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Console handler
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    console.setLevel(log_level)

    # Rotating file handler (10 MB × 5 backups)
    file_handler = RotatingFileHandler(log_file, maxBytes=10 * 1024 * 1024, backupCount=5)
    file_handler.setFormatter(formatter)
    file_handler.setLevel(log_level)

    app.logger.setLevel(log_level)
    app.logger.addHandler(console)
    app.logger.addHandler(file_handler)

    # Also configure root logger
    logging.basicConfig(level=log_level, handlers=[console, file_handler])


def get_logger(name: str) -> logging.Logger:
    """Get a named logger for use in service/utility modules."""
    return logging.getLogger(name)
