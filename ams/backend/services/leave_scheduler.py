"""
services/leave_scheduler.py — Background scheduler for leave due-notifications.

Fires an admin notification every morning for:
  • Leaves starting TODAY   → "Leave Due Today"
  • Leaves starting TOMORROW → "Leave Due Tomorrow"

Usage:
    from services.leave_scheduler import start_scheduler
    start_scheduler(app)   # called once in create_app()

Requires:
    pip install APScheduler
"""

from datetime import date, timedelta

from utils.logger import get_logger

logger = get_logger(__name__)

_scheduler = None  # module-level singleton so it isn't started twice


# ── Core notification logic (also called by the manual /notify-due endpoint) ──

def send_due_notifications() -> int:
    """
    Check for approved leaves starting today or tomorrow.
    Creates one admin alert per leave found.
    Returns the count of notifications created.
    """
    from config.database import db
    from sqlalchemy import text
    from services.notification_service import NotificationService

    today    = date.today()
    tomorrow = today + timedelta(days=1)
    count    = 0

    try:
        rows = db.session.execute(text("""
            SELECT lr.id,
                   lr.start_date,
                   lr.end_date,
                   lr.leave_type,
                   e.first_name || ' ' || e.last_name AS employee_name,
                   d.name                              AS department
            FROM leave_requests lr
            JOIN employees  e ON lr.employee_id = e.id
            LEFT JOIN departments d ON e.department_id = d.id
            WHERE lr.status = 'approved'
              AND lr.start_date IN (:today, :tomorrow)
        """), {"today": today, "tomorrow": tomorrow}).fetchall()

        for row in rows:
            is_today = str(row.start_date) == str(today)
            when     = "today" if is_today else "tomorrow"
            dept     = row.department or "N/A"
            ltype    = (row.leave_type or "leave").replace("_", " ").title()

            NotificationService.create_alert(
                title=f"{ltype} Due {when.capitalize()}",
                message=(
                    f"{row.employee_name} ({dept}) starts {ltype.lower()} "
                    f"{when} and returns after {row.end_date}."
                ),
                notif_type="warning" if is_today else "info",
                metadata={
                    "leave_id":  str(row.id),
                    "due_when":  when,
                    "leave_type": row.leave_type,
                },
            )
            count += 1

        if count:
            logger.info(f"leave_scheduler: sent {count} due-leave notification(s)")
        else:
            logger.info("leave_scheduler: no leaves due today or tomorrow")

    except Exception as exc:
        logger.error(f"leave_scheduler: error during notification job — {exc}")

    return count


# ── Scheduler bootstrap ────────────────────────────────────────

def start_scheduler(app):
    """
    Start the APScheduler background job.
    Safe to call multiple times — only one scheduler instance is created.
    Runs the job every day at 07:00 server time.
    """
    global _scheduler
    if _scheduler is not None:
        return _scheduler

    try:
        from apscheduler.schedulers.background import BackgroundScheduler
        from apscheduler.triggers.cron import CronTrigger
    except ImportError:
        logger.warning(
            "APScheduler not installed — leave due-notifications will not run automatically. "
            "Install it with:  pip install APScheduler"
        )
        return None

    def _job():
        with app.app_context():
            send_due_notifications()

    _scheduler = BackgroundScheduler(daemon=True)
    _scheduler.add_job(
        func=_job,
        trigger=CronTrigger(hour=7, minute=0),
        id="leave_due_notifier",
        replace_existing=True,
        misfire_grace_time=3600,   # retry within 1 hour if missed
    )
    _scheduler.start()
    logger.info("leave_scheduler: background scheduler started (fires daily at 07:00)")
    return _scheduler
