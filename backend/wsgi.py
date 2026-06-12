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

    # leave_requests has no SQLAlchemy model (raw-SQL feature),
    # so create_all() can't create it. Do it explicitly.
    from sqlalchemy import text
    db.session.execute(text("""
        CREATE TABLE IF NOT EXISTS leave_requests (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
            start_date  DATE NOT NULL,
            end_date    DATE NOT NULL,
            reason      TEXT DEFAULT '',
            leave_type  VARCHAR(20) NOT NULL DEFAULT 'annual',
            status      VARCHAR(20) NOT NULL DEFAULT 'pending',
            approved_by UUID REFERENCES users(id),
            approved_at TIMESTAMPTZ,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    db.session.execute(text("""
        CREATE TABLE IF NOT EXISTS rfid_cards (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            card_uid    VARCHAR(64) NOT NULL UNIQUE,
            label       VARCHAR(100),
            is_assigned BOOLEAN NOT NULL DEFAULT FALSE,
            assigned_to UUID REFERENCES employees(id) ON DELETE SET NULL,
            first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            tap_count   INTEGER NOT NULL DEFAULT 0
        )
    """))
    db.session.commit()

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
