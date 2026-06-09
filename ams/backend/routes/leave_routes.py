
from datetime import date, datetime, timedelta, timezone
from flask import Blueprint, request, jsonify, g
from marshmallow import Schema, fields, validate, ValidationError
from sqlalchemy.exc import ProgrammingError, InternalError, OperationalError

from middleware.auth_middleware import token_required, admin_required
from config.database import db
from utils.logger import get_logger
from sqlalchemy import text


_MIGRATION_ERRORS = (ProgrammingError, InternalError, OperationalError)

def _is_missing_column(exc) -> bool:
    """True when the error is caused by a missing leave_type column."""
    msg = str(exc).lower()
    return "leave_type" in msg or "column" in msg and "does not exist" in msg

def _migration_error_response():
    """Return a clear 503 when leave_type column is missing."""
    try:
        db.session.rollback()
    except Exception:
        pass
    return jsonify({
        "error": (
            "Database migration required. "
            "Run:  python migrate_add_leave_type.py  "
            "from the backend directory, then restart the server."
        )
    }), 503

leave_bp = Blueprint("leave", __name__)
logger   = get_logger(__name__)


# ── Schemas ────────────────────────────────────────────────────

LEAVE_TYPES = ["annual", "sick", "emergency", "unpaid", "absence", "other"]


class ApplyLeaveSchema(Schema):
    start_date  = fields.Date(required=True)
    end_date    = fields.Date(required=True)
    reason      = fields.Str(load_default="", validate=validate.Length(max=500))
    leave_type  = fields.Str(load_default="annual",
                             validate=validate.OneOf(LEAVE_TYPES))


class ReviewLeaveSchema(Schema):
    status = fields.Str(
        required=True,
        validate=validate.OneOf(["approved", "rejected"])
    )


# ── Helper ─────────────────────────────────────────────────────

def _serialize(row) -> dict:
    """Convert SQLAlchemy row to JSON-safe dict."""
    d = dict(row._mapping)
    return {
        k: str(v) if hasattr(v, 'hex') else
           v.isoformat() if hasattr(v, 'isoformat') else v
        for k, v in d.items()
    }


# ── Employee: apply for leave ──────────────────────────────────

@leave_bp.route("/apply", methods=["POST"])
@token_required
def apply_leave():
    """POST /api/v1/leave/apply"""
    try:
        data = ApplyLeaveSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    user = g.current_user
    if not user.employee:
        return jsonify({"error": "No employee record linked to your account"}), 404

    start = data["start_date"]
    end   = data["end_date"]

    if end < start:
        return jsonify({"error": "End date must be after start date"}), 400

    if start < date.today():
        return jsonify({"error": "Cannot apply for leave in the past"}), 400

    # Check overlapping leave
    overlap = db.session.execute(text("""
        SELECT id FROM leave_requests
        WHERE employee_id = :emp_id
          AND status IN ('pending', 'approved')
          AND NOT (end_date < :start OR start_date > :end)
    """), {
        "emp_id": str(user.employee.id),
        "start":  start,
        "end":    end,
    }).fetchone()

    if overlap:
        return jsonify({
            "error": "You already have a leave request for overlapping dates"
        }), 400

    try:
        result = db.session.execute(text("""
            INSERT INTO leave_requests
                (employee_id, start_date, end_date, reason, leave_type, status, created_at)
            VALUES (:emp_id, :start, :end, :reason, :leave_type, 'pending', NOW())
            RETURNING id, employee_id, start_date, end_date,
                      reason, leave_type, status, created_at
        """), {
            "emp_id":     str(user.employee.id),
            "start":      start,
            "end":        end,
            "reason":     data.get("reason", ""),
            "leave_type": data.get("leave_type", "annual"),
        })
        db.session.commit()
    except _MIGRATION_ERRORS:
        return _migration_error_response()

    row = _serialize(result.fetchone())
    logger.info(f"Leave applied: {user.employee.full_name} {start} to {end}")

    # Notify admins
    try:
        from services.notification_service import NotificationService
        NotificationService.create_alert(
            title="New Leave Request",
            message=f"{user.employee.full_name} applied for leave: {start} to {end}",
            notif_type="info",
            metadata={"employee_id": str(user.employee.id)},
        )
    except Exception:
        pass

    return jsonify({"message": "Leave request submitted", "leave": row}), 201


# ── Employee: my leave requests ────────────────────────────────

@leave_bp.route("/my", methods=["GET"])
@token_required
def my_leaves():
    """GET /api/v1/leave/my"""
    user = g.current_user
    if not user.employee:
        return jsonify({"leaves": []}), 200

    try:
        rows = db.session.execute(text("""
            SELECT lr.id, lr.start_date, lr.end_date, lr.reason,
                   lr.leave_type, lr.status, lr.approved_at, lr.created_at,
                   u.email AS approved_by_email
            FROM leave_requests lr
            LEFT JOIN users u ON lr.approved_by = u.id
            WHERE lr.employee_id = :emp_id
            ORDER BY lr.created_at DESC
        """), {"emp_id": str(user.employee.id)}).fetchall()
    except _MIGRATION_ERRORS:
        return _migration_error_response()

    return jsonify({"leaves": [_serialize(r) for r in rows]}), 200


# ── Employee: cancel pending leave ─────────────────────────────

@leave_bp.route("/<uuid:leave_id>/cancel", methods=["PUT"])
@token_required
def cancel_leave(leave_id):
    """PUT /api/v1/leave/:id/cancel"""
    user = g.current_user
    if not user.employee:
        return jsonify({"error": "No employee record"}), 404

    result = db.session.execute(text("""
        UPDATE leave_requests
        SET status = 'cancelled'
        WHERE id = :id
          AND employee_id = :emp_id
          AND status = 'pending'
        RETURNING id
    """), {
        "id":     str(leave_id),
        "emp_id": str(user.employee.id),
    })
    db.session.commit()

    if not result.fetchone():
        return jsonify({"error": "Leave not found or already processed"}), 404

    return jsonify({"message": "Leave request cancelled"}), 200


# ── Admin: all leave requests ──────────────────────────────────

@leave_bp.route("/all", methods=["GET"])
@admin_required
def all_leaves():
    """GET /api/v1/leave/all?status=pending&page=1"""
    status = request.args.get("status")
    search = request.args.get("search", "").strip()
    page   = int(request.args.get("page", 1))
    limit  = 30
    offset = (page - 1) * limit

    # Build dynamic WHERE clause
    conditions = ["1=1"]
    params     = {"limit": limit, "offset": offset}

    if status:
        conditions.append("lr.status = :status")
        params["status"] = status

    if search:
        conditions.append(
            "(e.first_name ILIKE :search OR e.last_name ILIKE :search "
            "OR (e.first_name || ' ' || e.last_name) ILIKE :search "
            "OR e.employee_id ILIKE :search)"
        )
        params["search"] = f"%{search}%"

    where = " AND ".join(conditions)

    try:
        rows = db.session.execute(text(f"""
            SELECT lr.id, lr.start_date, lr.end_date, lr.reason,
                   lr.leave_type, lr.status, lr.approved_at, lr.created_at,
                   e.first_name || ' ' || e.last_name AS employee_name,
                   e.employee_id                       AS emp_code,
                   d.name                              AS department
            FROM leave_requests lr
            JOIN employees  e ON lr.employee_id = e.id
            LEFT JOIN departments d ON e.department_id = d.id
            WHERE {where}
            ORDER BY lr.created_at DESC
            LIMIT :limit OFFSET :offset
        """), params).fetchall()

        # Count total (without limit/offset)
        count_params = {k: v for k, v in params.items()
                        if k not in ("limit", "offset")}
        total = db.session.execute(text(f"""
            SELECT COUNT(*)
            FROM leave_requests lr
            JOIN employees e ON lr.employee_id = e.id
            WHERE {where}
        """), count_params).scalar() or 0
    except _MIGRATION_ERRORS:
        return _migration_error_response()

    return jsonify({
        "leaves": [_serialize(r) for r in rows],
        "total":  total,
        "page":   page,
        "pages":  max(1, (total + limit - 1) // limit),
    }), 200


# ── Admin: approve or reject ───────────────────────────────────

@leave_bp.route("/<uuid:leave_id>/review", methods=["PUT"])
@admin_required
def review_leave(leave_id):
    """PUT /api/v1/leave/:id/review  body: { status: approved|rejected }"""
    try:
        data = ReviewLeaveSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    result = db.session.execute(text("""
        UPDATE leave_requests
        SET status      = :status,
            approved_by = :approver,
            approved_at = NOW()
        WHERE id = :id AND status = 'pending'
        RETURNING id, employee_id, start_date, end_date, status
    """), {
        "id":       str(leave_id),
        "status":   data["status"],
        "approver": str(g.current_user.id),
    })
    db.session.commit()

    row = result.fetchone()
    if not row:
        return jsonify({
            "error": "Leave request not found or already reviewed"
        }), 404

    r = _serialize(row)

    # If approved, mark those days as on_leave in attendance_logs
    if data["status"] == "approved":
        try:
            db.session.execute(text("""
                INSERT INTO attendance_logs
                    (employee_id, attendance_date, status, clock_in_method)
                SELECT :emp_id, d::date, 'on_leave', 'manual'
                FROM generate_series(
                    :start::date,
                    :end::date,
                    '1 day'::interval
                ) d
                WHERE EXTRACT(DOW FROM d) NOT IN (0, 6)
                ON CONFLICT (employee_id, attendance_date)
                DO UPDATE SET status = 'on_leave'
            """), {
                "emp_id": str(r["employee_id"]),
                "start":  r["start_date"],
                "end":    r["end_date"],
            })
            db.session.commit()
        except Exception as ex:
            db.session.rollback()
            logger.warning(f"Could not auto-mark leave in attendance: {ex}")

    # Notify the employee whose leave was reviewed
    try:
        from services.notification_service import NotificationService
        emp_row = db.session.execute(text("""
            SELECT e.first_name || ' ' || e.last_name AS full_name
            FROM employees e
            WHERE e.id = :emp_id
        """), {"emp_id": str(r["employee_id"])}).fetchone()
        emp_name = emp_row[0] if emp_row else "Employee"
        action   = "approved" if data["status"] == "approved" else "rejected"
        NotificationService.create_alert(
            title=f"Leave Request {action.capitalize()}",
            message=(
                f"Your leave request ({r['start_date']} to {r['end_date']}) "
                f"has been {action} by {g.current_user.email}."
            ),
            notif_type="success" if action == "approved" else "warning",
            metadata={"employee_id": str(r["employee_id"]),
                      "leave_id":    str(leave_id)},
        )
    except Exception:
        pass

    try:
        admin_email = g.current_user.email
    except Exception:
        admin_email = "admin"
    logger.info(f"Leave {leave_id} {data['status']} by {admin_email}")
    return jsonify({
        "message": f"Leave request {data['status']}",
        "status":  data["status"],
    }), 200


# ── Admin: pending count (dashboard badge) ─────────────────────

@leave_bp.route("/pending-count", methods=["GET"])
@admin_required
def pending_count():
    """GET /api/v1/leave/pending-count"""
    count = db.session.execute(text(
        "SELECT COUNT(*) FROM leave_requests WHERE status = 'pending'"
    )).scalar() or 0
    return jsonify({"pending": count}), 200


@leave_bp.route("/admin-submit", methods=["POST"])
@admin_required
def admin_submit_leave():
    """
    POST /api/v1/leave/admin-submit
    Admin submits and auto-approves leave on behalf of an employee.
    Body: { employee_id, start_date, end_date, reason }
    """
    data        = request.json or {}
    employee_id = data.get("employee_id", "")
    start_str   = data.get("start_date", "")
    end_str     = data.get("end_date", "")
    reason      = data.get("reason", "")
    leave_type  = data.get("leave_type", "annual")

    if leave_type not in LEAVE_TYPES:
        return jsonify({"error": f"leave_type must be one of {LEAVE_TYPES}"}), 400

    if not employee_id or not start_str or not end_str:
        return jsonify({"error": "employee_id, start_date and end_date required"}), 400

    try:
        start = date.fromisoformat(start_str)
        end   = date.fromisoformat(end_str)
    except ValueError:
        return jsonify({"error": "Invalid date format. Use YYYY-MM-DD"}), 400

    if end < start:
        return jsonify({"error": "End date must be after start date"}), 400

    # Check for overlapping leave (admins are not exempt from data integrity)
    overlap = db.session.execute(text("""
        SELECT id FROM leave_requests
        WHERE employee_id = :emp_id
          AND status IN ('pending', 'approved')
          AND NOT (end_date < :start OR start_date > :end)
    """), {
        "emp_id": employee_id,
        "start":  start,
        "end":    end,
    }).fetchone()

    if overlap:
        return jsonify({
            "error": "This employee already has a leave request for overlapping dates"
        }), 400

    # Insert as approved directly (admin bypass)
    try:
        result = db.session.execute(text("""
            INSERT INTO leave_requests
                (employee_id, start_date, end_date, reason, leave_type,
                 status, approved_by, approved_at, created_at)
            VALUES
                (:emp_id, :start, :end, :reason, :leave_type,
                 'approved', :approver, NOW(), NOW())
            RETURNING id, employee_id, start_date, end_date, status
        """), {
            "emp_id":     employee_id,
            "start":      start,
            "end":        end,
            "reason":     reason,
            "leave_type": leave_type,
            "approver":   str(g.current_user.id),
        })
        db.session.commit()
    except _MIGRATION_ERRORS:
        return _migration_error_response()

    row = result.fetchone()
    if not row:
        return jsonify({"error": "Failed to create leave request"}), 500

    r = _serialize(row)

    # Mark attendance as on_leave for weekdays in range
    try:
        db.session.execute(text("""
            INSERT INTO attendance_logs
                (employee_id, attendance_date, status, clock_in_method)
            SELECT :emp_id, d::date, 'on_leave', 'manual'
            FROM generate_series(
                :start::date, :end::date, '1 day'::interval
            ) d
            WHERE EXTRACT(DOW FROM d) NOT IN (0, 6)
            ON CONFLICT (employee_id, attendance_date)
            DO UPDATE SET status = 'on_leave'
        """), {
            "emp_id": employee_id,
            "start":  start,
            "end":    end,
        })
        db.session.commit()
    except Exception as ex:
        db.session.rollback()
        logger.warning(f"Could not auto-mark attendance: {ex}")

    try:
        admin_email = g.current_user.email
    except Exception:
        admin_email = "admin"
    logger.info(
        f"Admin {admin_email} submitted approved leave "
        f"for employee {employee_id}: {start} to {end}"
    )
    return jsonify({
        "message": "Leave submitted and approved successfully",
        "leave":   r,
    }), 201


# ── Admin: upcoming leaves (next N days) ───────────────────────

@leave_bp.route("/upcoming", methods=["GET"])
@admin_required
def upcoming_leaves():
    """
    GET /api/v1/leave/upcoming?days=7
    Returns approved leaves whose start_date falls within the next `days` days
    (including today), sorted by start_date ASC.
    """
    days = min(int(request.args.get("days", 7)), 30)
    today = date.today()
    until = today + __import__("datetime").timedelta(days=days)

    try:
        rows = db.session.execute(text("""
            SELECT lr.id, lr.start_date, lr.end_date, lr.reason,
                   lr.leave_type, lr.status, lr.approved_at, lr.created_at,
                   e.first_name || ' ' || e.last_name AS employee_name,
                   e.employee_id                       AS emp_code,
                   d.name                              AS department
            FROM leave_requests lr
            JOIN employees  e ON lr.employee_id = e.id
            LEFT JOIN departments d ON e.department_id = d.id
            WHERE lr.status = 'approved'
              AND lr.start_date >= :today
              AND lr.start_date <= :until
            ORDER BY lr.start_date ASC
        """), {"today": today, "until": until}).fetchall()
    except _MIGRATION_ERRORS:
        return _migration_error_response()

    return jsonify({"leaves": [_serialize(r) for r in rows]}), 200


# ── Admin: manually trigger due-today notifications ────────────

@leave_bp.route("/notify-due", methods=["POST"])
@admin_required
def notify_due():
    """
    POST /api/v1/leave/notify-due
    Manually fires notifications for leaves starting today or tomorrow.
    The scheduler calls the same logic automatically each morning.
    """
    from services.leave_scheduler import send_due_notifications
    count = send_due_notifications()
    return jsonify({"message": f"Sent {count} due-leave notification(s)"}), 200