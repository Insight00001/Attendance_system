"""
services/notification_service.py — Notification creation and delivery
"""

from typing import Optional
from datetime import datetime, timezone

from config.database import db
from models import Notification, Employee, User
from utils.logger import get_logger

logger = get_logger(__name__)


class NotificationService:

    @staticmethod
    def create_alert(
        title: str,
        message: str,
        notif_type: str = "info",
        user_id: Optional[str] = None,
        employee_id: Optional[str] = None,
        metadata: Optional[dict] = None,
    ) -> Notification:
        """Create a notification (admin-targeted by default)."""
        notif = Notification(
            user_id=user_id,
            employee_id=employee_id,
            type=notif_type,
            title=title,
            message=message,
            metadata=metadata,
        )
        db.session.add(notif)
        db.session.commit()

        # Emit real-time notification to admins
        try:
            from app import socketio
            socketio.emit("notification.new", notif.to_dict(), room="admin_dashboard")
        except Exception:
            pass

        return notif

    @staticmethod
    def notify_employee(
        employee: Employee,
        title: str,
        message: str,
        notif_type: str = "info",
        metadata: Optional[dict] = None,
    ) -> Notification:
        """Send a notification to a specific employee."""
        notif = Notification(
            user_id=str(employee.user_id),
            employee_id=str(employee.id),
            type=notif_type,
            title=title,
            message=message,
            metadata=metadata,
        )
        db.session.add(notif)
        db.session.commit()

        try:
            from app import socketio
            socketio.emit("notification.new", notif.to_dict(), room=f"user_{employee.user_id}")
        except Exception:
            pass

        return notif

    @staticmethod
    def get_user_notifications(user_id: str, unread_only: bool = False, page: int = 1) -> dict:
        query = Notification.query.filter_by(user_id=user_id)
        if unread_only:
            query = query.filter_by(is_read=False)
        query = query.order_by(Notification.created_at.desc())
        pagination = query.paginate(page=page, per_page=30, error_out=False)
        return {
            "notifications": [n.to_dict() for n in pagination.items],
            "total": pagination.total,
            "unread_count": Notification.query.filter_by(user_id=user_id, is_read=False).count(),
        }

    @staticmethod
    def mark_read(notification_id: str, user_id: str) -> bool:
        notif = Notification.query.filter_by(id=notification_id, user_id=user_id).first()
        if not notif:
            return False
        notif.is_read = True
        notif.read_at = datetime.now(timezone.utc)
        db.session.commit()
        return True

    @staticmethod
    def mark_all_read(user_id: str) -> int:
        count = Notification.query.filter_by(user_id=user_id, is_read=False).update({
            "is_read": True,
            "read_at": datetime.now(timezone.utc),
        })
        db.session.commit()
        return count
