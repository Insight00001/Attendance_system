"""
AttendEase — Flask Application Entry Point
==========================================
Initializes the Flask app, registers blueprints, extensions, and SocketIO.
"""

from flask import Flask, jsonify
from flask_cors import CORS
from flask_socketio import SocketIO
from flask_mail import Mail

from config.config import Config
from config.database import db
from middleware.error_handler import register_error_handlers
from utils.logger import setup_logger

import os
from flask import send_from_directory

# ─── Extension singletons (imported by other modules) ────────
socketio = SocketIO()
mail = Mail()


def create_app(config_class: type = Config) -> Flask:
    """
    Application factory pattern.
    Usage:
        app = create_app()                    # production
        app = create_app(TestingConfig)       # testing
    """
    app = Flask(__name__)
    app.config.from_object(config_class)

    # ── Logging ──────────────────────────────────────────────
    setup_logger(app)

    # ── Extensions ───────────────────────────────────────────
    db.init_app(app)
    mail.init_app(app)

    CORS(
        app,
        resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}},
        supports_credentials=True,
    )

    socketio.init_app(
        app,
        cors_allowed_origins=app.config["CORS_ORIGINS"],
        # "threading" for local Windows dev; "eventlet" on Render
        # (set SOCKETIO_ASYNC_MODE=eventlet + gunicorn -k eventlet)
        async_mode=os.getenv("SOCKETIO_ASYNC_MODE", "threading"),
        logger=True,
        engineio_logger=False,
    )

    # ── Rate Limiter ──────────────────────────────────────────
    from middleware.rate_limiter import limiter
    limiter.init_app(app)

    # ── Register Blueprints ───────────────────────────────────
    from routes.auth_routes import auth_bp
    from routes.employee_routes import employee_bp
    from routes.attendance_routes import attendance_bp
    from routes.analytics_routes import analytics_bp
    from routes.notification_routes import notification_bp
    from routes.settings_routes import settings_bp
    #from routes.camera_routes import camera_bp
    from routes.rfid_routes import rfid_bp
    from routes.leave_routes import leave_bp

    API_PREFIX = "/api/v1"
    app.register_blueprint(auth_bp,         url_prefix=f"{API_PREFIX}/auth")
    app.register_blueprint(employee_bp,     url_prefix=f"{API_PREFIX}/employees")
    app.register_blueprint(attendance_bp,   url_prefix=f"{API_PREFIX}/attendance")
    app.register_blueprint(analytics_bp,    url_prefix=f"{API_PREFIX}/analytics")
    app.register_blueprint(notification_bp, url_prefix=f"{API_PREFIX}/notifications")
    app.register_blueprint(settings_bp,     url_prefix=f"{API_PREFIX}/settings")
    app.register_blueprint(rfid_bp,         url_prefix=f"{API_PREFIX}/rfid")
    app.register_blueprint(leave_bp,        url_prefix=f"{API_PREFIX}/leave")

    # ── Register SocketIO Events ──────────────────────────────
    from routes import socket_events  # noqa: F401

    # ── Error Handlers ────────────────────────────────────────
    register_error_handlers(app)

    # ── Health Check ──────────────────────────────────────────
    @app.route("/health")
    def health():
        try:
            # Test DB connection
            db.session.execute(db.text("SELECT 1"))
            db_status = "ok"
        except Exception as e:
            db_status = f"error: {str(e)}"

        return jsonify({
            "status": "ok",
            "service": "AttendEase API",
            "database": db_status,
        }), 200

    # ── Serve uploaded photos ─────────────────────────────────
 

    @app.route("/uploads/<path:filename>")
    def serve_upload(filename):
        upload_folder = os.path.abspath(
            app.config.get("UPLOAD_FOLDER", "uploads"))
        return send_from_directory(upload_folder, filename)

    # ── Auto-migration: ensure leave_type column exists ──────
    _ensure_leave_type_column(app)

    # ── Leave due-notification scheduler ─────────────────────
    # Fires admin alerts every morning for leaves starting today / tomorrow.
    # APScheduler must be installed: pip install APScheduler
    try:
        from services.leave_scheduler import start_scheduler
        start_scheduler(app)
    except Exception as _sched_err:
        app.logger.warning(f"Could not start leave scheduler: {_sched_err}")

    app.logger.info("AttendEase backend started OK")
    return app


def _ensure_leave_type_column(app: "Flask") -> None:
    """
    Idempotent startup migration: adds `leave_type` to `leave_requests`
    if the column doesn't already exist.  Runs inside the app context so
    it fires once per server process, before the first request is served.
    """
    with app.app_context():
        try:
            from config.database import db
            from sqlalchemy import text as _text

            col_exists = db.session.execute(_text("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_name  = 'leave_requests'
                  AND column_name = 'leave_type'
            """)).scalar()

            if not col_exists:
                db.session.execute(_text("""
                    ALTER TABLE leave_requests
                    ADD COLUMN leave_type VARCHAR(20) NOT NULL DEFAULT 'annual'
                """))
                db.session.commit()
                app.logger.info(
                    "Auto-migration: added leave_type column to leave_requests"
                )

                # Best-effort CHECK constraint
                try:
                    db.session.execute(_text("""
                        ALTER TABLE leave_requests
                        ADD CONSTRAINT chk_leave_type
                        CHECK (leave_type IN (
                            'annual','sick','emergency','unpaid','absence','other'
                        ))
                    """))
                    db.session.commit()
                except Exception:
                    db.session.rollback()   # constraint already exists or unsupported

        except Exception as _mig_err:
            app.logger.warning(
                f"Auto-migration for leave_type skipped: {_mig_err}"
            )