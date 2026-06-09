"""
routes/attendance_routes.py — Attendance endpoints (face clock-in/out, logs, export)
"""

import base64
import calendar as _cal
from datetime import date, timedelta
from flask import Blueprint, request, jsonify, g, make_response
from config.database import db
from sqlalchemy import text
from marshmallow import Schema, fields, ValidationError

from services.attendance_service import AttendanceService
from middleware.auth_middleware import token_required, admin_required
from middleware.rate_limiter import limiter

attendance_bp = Blueprint("attendance", __name__)


class FaceClockSchema(Schema):
    """Payload for face-based clock-in/out."""
    image_b64       = fields.Str(required=True)        # base64-encoded JPEG
    liveness_frames = fields.List(fields.Str(), load_default=[])  # base64 frames


class ManualClockSchema(Schema):
    employee_id = fields.UUID(required=True)
    notes       = fields.Str(load_default="")


# ── Face Clock-In ──────────────────────────────────────────────

@attendance_bp.route("/clock-in", methods=["POST"])
@limiter.limit("30 per minute")
def clock_in():
    """POST /api/v1/attendance/clock-in — face recognition clock-in"""
    try:
        data = FaceClockSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    from services.face_recognition_service import FaceRecognitionService
    image_bytes = FaceRecognitionService.base64_to_bytes(data["image_b64"])

    result, error = AttendanceService.clock_in_by_face(
        image_bytes=image_bytes,
        liveness_frames=data.get("liveness_frames", []),
    )

    if error:
        return jsonify({"error": error}), 400

    return jsonify(result), 200


# ── Face Clock-Out ─────────────────────────────────────────────

@attendance_bp.route("/clock-out", methods=["POST"])
@limiter.limit("30 per minute")
def clock_out():
    """POST /api/v1/attendance/clock-out"""
    try:
        data = FaceClockSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    from services.face_recognition_service import FaceRecognitionService
    image_bytes = FaceRecognitionService.base64_to_bytes(data["image_b64"])

    result, error = AttendanceService.clock_out_by_face(image_bytes=image_bytes)
    if error:
        return jsonify({"error": error}), 400

    return jsonify(result), 200


# ── Face Verify (identify only, no logging) ────────────────────

@attendance_bp.route("/face-verify", methods=["POST"])
def face_verify():
    """POST /api/v1/attendance/face-verify — identify face without logging"""
    body = request.json or {}
    image_b64 = body.get("image_b64", "")
    if not image_b64:
        return jsonify({"error": "image_b64 required"}), 400

    from services.face_recognition_service import FaceRecognitionService
    image_bytes = FaceRecognitionService.base64_to_bytes(image_b64)
    employee, confidence = FaceRecognitionService.identify_face(image_bytes)

    if not employee:
        return jsonify({"recognized": False, "confidence": confidence}), 200

    return jsonify({
        "recognized": True,
        "confidence": confidence,
        "employee": employee.to_dict(),
    }), 200


# ── Manual Clock-In (Admin) ────────────────────────────────────

@attendance_bp.route("/manual/clock-in", methods=["POST"])
@admin_required
def manual_clock_in():
    """POST /api/v1/attendance/manual/clock-in"""
    try:
        data = ManualClockSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    result, error = AttendanceService.manual_clock_in(
        str(data["employee_id"]), data.get("notes", "")
    )
    if error:
        return jsonify({"error": error}), 400

    return jsonify(result), 200


# ── Today's Attendance ─────────────────────────────────────────

@attendance_bp.route("/today", methods=["GET"])
@admin_required
def today_attendance():
    """GET /api/v1/attendance/today"""
    logs = AttendanceService.get_today_attendance()
    return jsonify({"date": date.today().isoformat(), "logs": logs, "count": len(logs)}), 200


# ── Paginated Logs ─────────────────────────────────────────────

@attendance_bp.route("/logs", methods=["GET"])
@admin_required
def attendance_logs():
    """GET /api/v1/attendance/logs?start_date=&end_date=&employee_id=&status=&page="""
    args = request.args

    result = AttendanceService.get_attendance_logs(
        start_date=date.fromisoformat(args["start_date"]) if args.get("start_date") else None,
        end_date=date.fromisoformat(args["end_date"]) if args.get("end_date") else None,
        employee_id=args.get("employee_id"),
        department_id=args.get("department_id"),
        status=args.get("status"),
        page=int(args.get("page", 1)),
        per_page=int(args.get("per_page", 50)),
    )
    return jsonify(result), 200


# ── Export CSV ────────────────────────────────────────────────

@attendance_bp.route("/export", methods=["GET"])
@admin_required
def export_attendance():
    """GET /api/v1/attendance/export?start_date=&end_date=&format=csv"""
    args = request.args
    start = date.fromisoformat(args.get("start_date", date.today().isoformat()))
    end   = date.fromisoformat(args.get("end_date", date.today().isoformat()))
    fmt   = args.get("format", "csv")

    if fmt == "csv":
        csv_bytes = AttendanceService.export_csv(start, end, args.get("employee_id"))
        response = make_response(csv_bytes)
        response.headers["Content-Type"] = "text/csv"
        response.headers["Content-Disposition"] = (
            f'attachment; filename="attendance_{start}_{end}.csv"'
        )
        return response

    return jsonify({"error": "Unsupported format. Use: csv"}), 400


# ── Employee: own attendance logs ─────────────────────────────

@attendance_bp.route("/my-logs", methods=["GET"])
@token_required
def my_attendance_logs():
    """
    GET /api/v1/attendance/my-logs?start_date=&end_date=&status=&page=
    Employees can only see their own logs.
    """
    user = g.current_user
    if not (hasattr(user, "employee") and user.employee):
        return jsonify({"logs": [], "total": 0, "pages": 1, "page": 1}), 200

    args = request.args
    result = AttendanceService.get_attendance_logs(
        start_date=date.fromisoformat(args["start_date"]) if args.get("start_date") else None,
        end_date=date.fromisoformat(args["end_date"])   if args.get("end_date")   else None,
        employee_id=str(user.employee.id),   # always filter to self
        status=args.get("status"),
        page=int(args.get("page", 1)),
        per_page=int(args.get("per_page", 50)),
    )
    return jsonify(result), 200


# ── Calendar view ──────────────────────────────────────────────

@attendance_bp.route("/calendar", methods=["GET"])
@token_required
def attendance_calendar():
    """
    GET /api/v1/attendance/calendar?year=2026&month=6&employee_id=xxx

    Returns a day→status map for every recorded day in the month.
    Admins can query any employee by passing employee_id.
    Employees always get their own data.
    """
    args  = request.args
    year  = int(args.get("year",  date.today().year))
    month = int(args.get("month", date.today().month))

    user = g.current_user

    # Resolve which employee to query
    if user.user_role == "admin":
        employee_id = args.get("employee_id")
        if not employee_id and hasattr(user, "employee") and user.employee:
            employee_id = str(user.employee.id)
    else:
        if not (hasattr(user, "employee") and user.employee):
            return jsonify({"year": year, "month": month, "days": {}}), 200
        employee_id = str(user.employee.id)

    if not employee_id:
        return jsonify({"year": year, "month": month, "days": {}}), 200

    _, days_in_month = _cal.monthrange(year, month)
    start = date(year, month, 1)
    end   = date(year, month, days_in_month)

    rows = db.session.execute(text("""
        SELECT attendance_date,
               status,
               clock_in,
               clock_out,
               COALESCE(is_late,    FALSE) AS is_late,
               COALESCE(late_minutes, 0)   AS late_minutes
        FROM attendance_logs
        WHERE employee_id = :emp_id
          AND attendance_date >= :start
          AND attendance_date <= :end
        ORDER BY attendance_date
    """), {"emp_id": employee_id, "start": start, "end": end}).fetchall()

    days = {}
    for row in rows:
        d = str(row.attendance_date)
        days[d] = {
            "status":        row.status,
            "clock_in":      row.clock_in.isoformat()  if row.clock_in  else None,
            "clock_out":     row.clock_out.isoformat() if row.clock_out else None,
            "is_late":       bool(row.is_late),
            "late_minutes":  int(row.late_minutes or 0),
        }

    # Overlay leave_requests so pending/approved leaves always show,
    # even when the attendance_logs insert failed or leave is still pending.
    leave_rows = db.session.execute(text("""
        SELECT lr.start_date, lr.end_date, lr.status AS leave_status, lr.leave_type
        FROM leave_requests lr
        WHERE lr.employee_id = :emp_id
          AND lr.status IN ('pending', 'approved')
          AND lr.end_date   >= :start
          AND lr.start_date <= :end
    """), {"emp_id": employee_id, "start": start, "end": end}).fetchall()

    for lr in leave_rows:
        d = lr.start_date
        while d <= lr.end_date:
            if start <= d <= end:
                key = str(d)
                # Only overlay if there is no real clock-in/out record for this day
                existing = days.get(key, {})
                if not existing.get("clock_in"):
                    days[key] = {
                        "status":       "on_leave" if lr.leave_status == "approved" else "leave_pending",
                        "clock_in":     None,
                        "clock_out":    None,
                        "is_late":      False,
                        "late_minutes": 0,
                        "leave_type":   lr.leave_type,
                        "leave_status": lr.leave_status,
                    }
            d = d + timedelta(days=1)

    return jsonify({
        "year":          year,
        "month":         month,
        "days_in_month": days_in_month,
        "employee_id":   employee_id,
        "days":          days,
    }), 200
