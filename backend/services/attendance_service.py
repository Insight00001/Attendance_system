"""
services/attendance_service.py
Attendance business logic: clock-in, clock-out, late detection, exports.
"""

import csv
import io
import os
from datetime import datetime, timezone, date, timedelta
from typing import Optional, Tuple

from flask import current_app
from sqlalchemy import func, and_

from config.database import db
from models import Employee, AttendanceLog, Notification
from services.face_recognition_service import FaceRecognitionService
from services.notification_service import NotificationService
from utils.logger import get_logger

logger = get_logger(__name__)


class AttendanceService:
    """
    Clock-in / Clock-out logic with:
    - Face recognition integration
    - Late detection
    - Duplicate prevention
    - Overtime calculation
    """

    # ── Clock In ─────────────────────────────────────────────

    @classmethod
    def clock_in_by_face(
        cls,
        image_bytes: bytes,
        liveness_frames: Optional[list] = None,
        method: str = "face_recognition",
    ) -> Tuple[Optional[dict], Optional[str]]:
        """
        Process a clock-in from a face image.
        1. Liveness check (if frames provided)
        2. Face identification
        3. Duplicate check
        4. Log creation
        5. Emit WebSocket event
        """

        # ── Liveness Detection ────────────────────────────
        if liveness_frames:
            is_live = FaceRecognitionService.detect_liveness_from_frames(liveness_frames)
            if not is_live:
                logger.warning("Liveness check failed — potential spoofing attempt")
                NotificationService.create_alert(
                    title="Liveness Check Failed",
                    message="A clock-in attempt failed liveness detection. Possible photo spoofing.",
                    notif_type="alert",
                )
                return None, "Liveness check failed. Please blink naturally in front of the camera."

        # ── Face Identification ───────────────────────────
        employee, confidence = FaceRecognitionService.identify_face(image_bytes)

        if not employee:
            # Log unknown face snapshot
            snapshot_path = FaceRecognitionService.save_snapshot(image_bytes, "unknown")
            NotificationService.create_alert(
                title="Unknown Face Detected",
                message=f"Unrecognized face attempted clock-in (confidence: {confidence:.1f}%)",
                notif_type="warning",
                metadata={"snapshot": snapshot_path, "confidence": confidence},
            )
            return None, f"Face not recognized (confidence: {confidence:.1f}%). Please try again."

        # ── Check Duplicate Clock-in ──────────────────────
        today = date.today()
        existing = AttendanceLog.query.filter_by(
            employee_id=employee.id,
            attendance_date=today,
        ).first()

        if existing and existing.clock_in:
            if existing.clock_out:
                return None, f"{employee.full_name} has already completed attendance today."
            # Already clocked in but not out → redirect to clock-out
            return {"already_clocked_in": True, "log_id": str(existing.id), "employee": employee.to_dict()}, None

        # ── Save snapshot ─────────────────────────────────
        snapshot_path = FaceRecognitionService.save_snapshot(image_bytes, "clock_in")

        # ── Compute lateness ─────────────────────────────
        # Store timestamps in UTC, but compare lateness in LOCAL time —
        # shift_start is a local wall-clock time (e.g. 09:00), not UTC.
        now = datetime.now(timezone.utc)
        local_now = datetime.now()
        shift_start_dt = datetime.combine(today, employee.shift_start)
        grace_end = shift_start_dt + timedelta(minutes=employee.late_threshold)
        is_late = local_now > grace_end
        late_minutes = max(0, int((local_now - grace_end).total_seconds() / 60)) if is_late else 0

        # ── Create or update attendance log ───────────────
        if existing:
            existing.clock_in = now
            existing.clock_in_method = method
            existing.status = "late" if is_late else "present"
            existing.is_late = is_late
            existing.late_minutes = late_minutes
            existing.confidence_in = confidence
            existing.clock_in_photo = snapshot_path
            log = existing
        else:
            log = AttendanceLog(
                employee_id=employee.id,
                attendance_date=today,
                clock_in=now,
                clock_in_method=method,
                status="late" if is_late else "present",
                is_late=is_late,
                late_minutes=late_minutes,
                confidence_in=confidence,
                clock_in_photo=snapshot_path,
            )
            db.session.add(log)

        db.session.commit()

        result = {
            "log": log.to_dict(),
            "employee": employee.to_dict(),
            "is_late": is_late,
            "late_minutes": late_minutes,
            "confidence": confidence,
            "message": f"Welcome, {employee.first_name}! {'You are late by ' + str(late_minutes) + ' minutes.' if is_late else 'On time!'}",
        }

        # ── WebSocket broadcast ───────────────────────────
        cls._broadcast_clock_in(employee, log, is_late)

        # ── Notify if late ────────────────────────────────
        if is_late:
            NotificationService.notify_employee(
                employee=employee,
                title="Late Arrival",
                message=f"You clocked in {late_minutes} minutes late today.",
                notif_type="warning",
            )

        logger.info(f"Clock-in: {employee.full_name} @ {now} (late={is_late})")
        return result, None

    # ── Clock Out ─────────────────────────────────────────────

    @classmethod
    def clock_out_by_face(
        cls,
        image_bytes: bytes,
        method: str = "face_recognition",
    ) -> Tuple[Optional[dict], Optional[str]]:
        """Process clock-out from face image."""
        employee, confidence = FaceRecognitionService.identify_face(image_bytes)

        if not employee:
            return None, "Face not recognized. Please try again."

        today = date.today()
        log = AttendanceLog.query.filter_by(
            employee_id=employee.id,
            attendance_date=today,
        ).first()

        if not log or not log.clock_in:
            return None, f"{employee.full_name} has no clock-in record for today."

        if log.clock_out:
            return None, f"{employee.full_name} has already clocked out today."

        now = datetime.now(timezone.utc)
        snapshot_path = FaceRecognitionService.save_snapshot(image_bytes, "clock_out")

        log.clock_out = now
        log.clock_out_method = method
        log.confidence_out = confidence
        log.clock_out_photo = snapshot_path

        # working_minutes computed by DB trigger; set here too for immediate return
        if log.clock_in:
            total_minutes = int((now - log.clock_in).total_seconds() / 60)
            log.working_minutes = total_minutes
            log.overtime_minutes = max(0, total_minutes - 480)  # >8h

        db.session.commit()

        hours = log.working_minutes // 60
        mins = log.working_minutes % 60
        result = {
            "log": log.to_dict(),
            "employee": employee.to_dict(),
            "working_minutes": log.working_minutes,
            "overtime_minutes": log.overtime_minutes,
            "message": f"Goodbye, {employee.first_name}! You worked {hours}h {mins}m today.",
        }

        cls._broadcast_clock_out(employee, log)
        logger.info(f"Clock-out: {employee.full_name} @ {now}")
        return result, None

    # ── Manual Clock In/Out ───────────────────────────────────

    @classmethod
    def manual_clock_in(cls, employee_id: str, notes: str = "") -> Tuple[Optional[dict], Optional[str]]:
        """Admin can manually log an employee's clock-in."""
        employee = Employee.query.filter_by(id=employee_id, employment_status="active").first()
        if not employee:
            return None, "Employee not found"

        today = date.today()
        existing = AttendanceLog.query.filter_by(employee_id=employee_id, attendance_date=today).first()
        if existing and existing.clock_in:
            return None, "Employee already has a clock-in record today"

        # Compare lateness in LOCAL time — shift_start is local wall-clock
        now = datetime.now(timezone.utc)
        local_now = datetime.now()
        shift_start_dt = datetime.combine(today, employee.shift_start)
        grace_end = shift_start_dt + timedelta(minutes=employee.late_threshold)
        is_late = local_now > grace_end
        late_minutes = max(0, int((local_now - grace_end).total_seconds() / 60)) if is_late else 0

        if existing:
            existing.clock_in = now
            existing.clock_in_method = "manual"
            existing.status = "late" if is_late else "present"
            existing.is_late = is_late
            existing.late_minutes = late_minutes
            existing.notes = notes
            log = existing
        else:
            log = AttendanceLog(
                employee_id=employee_id,
                attendance_date=today,
                clock_in=now,
                clock_in_method="manual",
                status="late" if is_late else "present",
                is_late=is_late,
                late_minutes=late_minutes,
                notes=notes,
            )
            db.session.add(log)

        db.session.commit()
        return {"log": log.to_dict()}, None

    # ── Query Methods ─────────────────────────────────────────

    @staticmethod
    def get_today_attendance() -> list:
        """Return all attendance records for today."""
        today = date.today()
        logs = (
            AttendanceLog.query
            .filter_by(attendance_date=today)
            .join(Employee)
            .order_by(AttendanceLog.clock_in.asc())
            .all()
        )
        return [l.to_dict() for l in logs]

    @staticmethod
    def get_attendance_logs(
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        employee_id: Optional[str] = None,
        department_id: Optional[str] = None,
        status: Optional[str] = None,
        page: int = 1,
        per_page: int = 50,
    ) -> dict:
        """Paginated, filtered attendance log query."""
        query = AttendanceLog.query.join(Employee)

        if start_date:
            query = query.filter(AttendanceLog.attendance_date >= start_date)
        if end_date:
            query = query.filter(AttendanceLog.attendance_date <= end_date)
        if employee_id:
            query = query.filter(AttendanceLog.employee_id == employee_id)
        if department_id:
            query = query.filter(Employee.department_id == department_id)
        if status:
            query = query.filter(AttendanceLog.status == status)

        query = query.order_by(AttendanceLog.attendance_date.desc(), AttendanceLog.clock_in.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)

        return {
            "logs": [l.to_dict() for l in pagination.items],
            "total": pagination.total,
            "pages": pagination.pages,
            "page": page,
            "per_page": per_page,
        }

    # ── Export ────────────────────────────────────────────────

    @staticmethod
    def export_csv(start_date: date, end_date: date, employee_id: Optional[str] = None) -> bytes:
        """Export attendance records as CSV bytes."""
        query = (
            AttendanceLog.query
            .filter(
                AttendanceLog.attendance_date.between(start_date, end_date)
            )
            .join(Employee)
            .order_by(AttendanceLog.attendance_date, Employee.last_name)
        )
        if employee_id:
            query = query.filter(AttendanceLog.employee_id == employee_id)

        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow([
            "Date", "Employee ID", "Name", "Department",
            "Clock In", "Clock Out", "Status", "Late", "Late (mins)",
            "Working (mins)", "Overtime (mins)", "Method",
        ])

        for log in query.all():
            emp = log.employee
            writer.writerow([
                log.attendance_date.isoformat(),
                emp.employee_id,
                emp.full_name,
                emp.department.name if emp.department else "",
                log.clock_in.strftime("%H:%M:%S") if log.clock_in else "",
                log.clock_out.strftime("%H:%M:%S") if log.clock_out else "",
                log.status,
                "Yes" if log.is_late else "No",
                log.late_minutes,
                log.working_minutes,
                log.overtime_minutes,
                log.clock_in_method,
            ])

        return output.getvalue().encode("utf-8")

    # ── WebSocket Helpers ─────────────────────────────────────

    @staticmethod
    def _broadcast_clock_in(employee: Employee, log: AttendanceLog, is_late: bool):
        """Emit clock-in event to all admin dashboard clients."""
        try:
            from app import socketio
            socketio.emit("attendance.clock_in", {
                "employee_id": str(employee.id),
                "employee_name": employee.full_name,
                "department": employee.department.name if employee.department else None,
                "photo_url": employee.photo_url,
                "timestamp": log.clock_in.isoformat(),
                "is_late": is_late,
                "late_minutes": log.late_minutes,
            }, room="admin_dashboard")
        except Exception as e:
            logger.error(f"WebSocket emit error: {e}")

    @staticmethod
    def _broadcast_clock_out(employee: Employee, log: AttendanceLog):
        """Emit clock-out event."""
        try:
            from app import socketio
            socketio.emit("attendance.clock_out", {
                "employee_id": str(employee.id),
                "employee_name": employee.full_name,
                "timestamp": log.clock_out.isoformat(),
                "working_minutes": log.working_minutes,
            }, room="admin_dashboard")
        except Exception as e:
            logger.error(f"WebSocket emit error: {e}")
