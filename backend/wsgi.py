"""WSGI entry point for Gunicorn."""
import os

# On cloud deploys (Render) we run gunicorn with the eventlet worker so
# Socket.IO gets real WebSockets. Eventlet must monkey-patch the stdlib
# BEFORE anything else is imported.
if os.getenv("SOCKETIO_ASYNC_MODE") == "eventlet":
    import eventlet
    eventlet.monkey_patch()

from app import create_app, socketio

app = create_app()

# ── Ensure schema exists (idempotent; no-op if tables are present) ──
with app.app_context():
    from config.database import db
    import models  # noqa: F401 — registers all models with SQLAlchemy

    db.create_all()

    # Seed the initial admin once (skip if already present)
    if os.getenv("SEED_ADMIN", "true").lower() == "true":
        try:
            from services.auth_service import AuthService
            AuthService.create_admin(
                os.getenv("ADMIN_EMAIL", "admin@attendease.com"),
                os.getenv("ADMIN_PASSWORD", "Admin@1234"),
                "System Admin",
            )
        except Exception:
            pass  # admin already exists

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=5000, debug=False)
