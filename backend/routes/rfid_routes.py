
import os
from datetime import date, datetime, timezone, timedelta
from flask import Blueprint, request, jsonify, g
from sqlalchemy import text

from config.database import db
from models import Employee
from middleware.auth_middleware import token_required, admin_required
from services.notification_service import NotificationService
from utils.logger import get_logger

rfid_bp = Blueprint("rfid", __name__)
logger  = get_logger(__name__)

# Per-customer key — MUST be set in the environment (no default:
# a shared fallback key would let one customer's reader talk to
# another customer's server).
RFID_API_KEY = os.getenv("CAMERA_API_KEY", "")


def _verify_key():
    if not RFID_API_KEY:        # unconfigured server → reject all
        return False
    key = request.headers.get("X-Camera-Key") or request.args.get("key", "")
    return key == RFID_API_KEY


# ── Helper: register or update card in rfid_cards table ───────

def _register_card(card_uid: str):
    """
    Insert card if new, or update last_seen + tap_count if already seen.
    Returns True if card is brand new.
    """
    existing = db.session.execute(text(
        "SELECT id FROM rfid_cards WHERE card_uid = :uid"
    ), {"uid": card_uid}).fetchone()

    if existing:
        db.session.execute(text("""
            UPDATE rfid_cards
            SET last_seen = NOW(), tap_count = tap_count + 1
            WHERE card_uid = :uid
        """), {"uid": card_uid})
        db.session.commit()
        return False   # not new
    else:
        db.session.execute(text("""
            INSERT INTO rfid_cards (card_uid, is_assigned, first_seen, last_seen, tap_count)
            VALUES (:uid, FALSE, NOW(), NOW(), 1)
        """), {"uid": card_uid})
        db.session.commit()
        return True    # brand new card


# ── ESP8266: card tap ──────────────────────────────────────────

@rfid_bp.route("/tap", methods=["POST"])
def rfid_tap():
    """
    POST /api/v1/rfid/tap
    Called by ESP8266 on every card tap.
    """
    if not _verify_key():
        return jsonify({"success": False, "message": "Invalid API key"}), 401

    data      = request.json or {}
    card_uid  = data.get("card_uid", "").strip().upper()
    reader_id = data.get("reader_id", "unknown")

    if not card_uid:
        return jsonify({"success": False, "message": "card_uid required"}), 400

    logger.info(f"RFID tap: {card_uid} from reader '{reader_id}'")

    # ── Find employee by card ──────────────────────────────────
    employee = Employee.query.filter_by(
        card_uid=card_uid,
        employment_status="active"
    ).first()

    if not employee:
        # Register unknown card in rfid_cards table
        is_new = _register_card(card_uid)

        if is_new:
            logger.info(f"New unassigned card registered: {card_uid}")
            # Notify admin via WebSocket
            try:
                from app import socketio
                socketio.emit("rfid.new_card", {
                    "card_uid":  card_uid,
                    "reader_id": reader_id,
                    "message":   f"New RFID card detected: {card_uid}",
                }, room="admin_dashboard")
            except Exception:
                pass

            NotificationService.create_alert(
                title="New RFID Card Detected",
                message=f"Unassigned card: {card_uid} at {reader_id}. Assign it to an employee.",
                notif_type="info",
                metadata={"card_uid": card_uid, "reader_id": reader_id},
            )
        else:
            logger.warning(f"Unknown card tapped again: {card_uid}")

        return jsonify({
            "success": False,
            "message": "Card not assigned. Contact admin.",
            "card_uid": card_uid,
        }), 200

    # ── Determine clock in or out ──────────────────────────────
    today     = date.today()
    from models import AttendanceLog
    today_log = AttendanceLog.query.filter_by(
        employee_id=employee.id,
        attendance_date=today,
    ).first()

    MIN_WORK_MINUTES = 30  # must be clocked in at least this long before card clock-out

    if not today_log or not today_log.clock_in:
        action = "clock_in"
    elif not today_log.clock_out:
        elapsed = (datetime.now(timezone.utc) - today_log.clock_in).total_seconds() / 60
        if elapsed < MIN_WORK_MINUTES:
            return jsonify({
                "success": False,
                "employee_name": employee.full_name,
                "action": "too_soon",
                "message": f"Clock-out ignored — only {int(elapsed)} min since clock-in. "
                           f"Minimum is {MIN_WORK_MINUTES} min.",
            }), 200
        action = "clock_out"
    else:
        return jsonify({
            "success":       True,
            "employee_name": employee.full_name,
            "action":        "already_done",
            "message":       f"{employee.first_name} has completed attendance today.",
        }), 200

    now = datetime.now(timezone.utc)

    if action == "clock_in":
        # Compare lateness in LOCAL time — shift_start is local wall-clock
        local_now      = datetime.now()
        shift_start_dt = datetime.combine(today, employee.shift_start)
        grace_end  = shift_start_dt + timedelta(minutes=employee.late_threshold)
        is_late    = local_now > grace_end
        late_mins  = max(0, int((local_now - grace_end).total_seconds() / 60)) if is_late else 0

        if today_log:
            today_log.clock_in        = now
            today_log.clock_in_method = "card"
            today_log.status          = "late" if is_late else "present"
            today_log.is_late         = is_late
            today_log.late_minutes    = late_mins
            log = today_log
        else:
            from models import AttendanceLog
            log = AttendanceLog(
                employee_id    = employee.id,
                attendance_date= today,
                clock_in       = now,
                clock_in_method= "card",
                status         = "late" if is_late else "present",
                is_late        = is_late,
                late_minutes   = late_mins,
            )
            db.session.add(log)

        db.session.commit()

        try:
            from app import socketio
            socketio.emit("attendance.clock_in", {
                "employee_id":   str(employee.id),
                "employee_name": employee.full_name,
                "department":    employee.department.name if employee.department else None,
                "timestamp":     log.clock_in.isoformat(),
                "is_late":       is_late,
                "late_minutes":  late_mins,
                "method":        "card",
            }, room="admin_dashboard")
        except Exception:
            pass

        message = f"Welcome, {employee.first_name}!"
        if is_late:
            message += f" {late_mins} minute(s) late."
        else:
            message += " On time!"

        logger.info(f"Clock-in: {employee.full_name} | late={is_late}")
        return jsonify({
            "success":       True,
            "employee_name": employee.full_name,
            "employee_id":   employee.employee_id,
            "action":        "clock_in",
            "message":       message,
            "is_late":       is_late,
            "late_minutes":  late_mins,
        }), 200

    else:
        total_mins    = int((now - today_log.clock_in).total_seconds() / 60)
        overtime_mins = max(0, total_mins - 480)

        today_log.clock_out        = now
        today_log.clock_out_method = "card"
        today_log.working_minutes  = total_mins
        today_log.overtime_minutes = overtime_mins
        db.session.commit()

        hours = total_mins // 60
        mins  = total_mins % 60

        try:
            from app import socketio
            socketio.emit("attendance.clock_out", {
                "employee_id":    str(employee.id),
                "employee_name":  employee.full_name,
                "timestamp":      today_log.clock_out.isoformat(),
                "working_minutes": total_mins,
            }, room="admin_dashboard")
        except Exception:
            pass

        logger.info(f"Clock-out: {employee.full_name} | {hours}h {mins}m")
        return jsonify({
            "success":         True,
            "employee_name":   employee.full_name,
            "employee_id":     employee.employee_id,
            "action":          "clock_out",
            "message":         f"Goodbye, {employee.first_name}! Worked {hours}h {mins}m.",
            "working_minutes": total_mins,
            "overtime_minutes": overtime_mins,
        }), 200


# ── Admin: list unassigned cards ───────────────────────────────

@rfid_bp.route("/cards", methods=["GET"])
@admin_required
def list_cards():
    """
    GET /api/v1/rfid/cards
    Returns only unassigned cards (is_assigned = FALSE).
    """
    rows = db.session.execute(text("""
        SELECT id, card_uid, label, is_assigned,
               first_seen, last_seen, tap_count
        FROM rfid_cards
        WHERE is_assigned = FALSE
        ORDER BY last_seen DESC
    """)).fetchall()

    cards = []
    for row in rows:
        d = dict(row._mapping)
        cards.append({
            "id":          str(d["id"]),
            "card_uid":    d["card_uid"],
            "label":       d["label"],
            "is_assigned": d["is_assigned"],
            "first_seen":  d["first_seen"].isoformat() if d["first_seen"] else None,
            "last_seen":   d["last_seen"].isoformat() if d["last_seen"] else None,
            "tap_count":   d["tap_count"],
        })

    return jsonify({"cards": cards, "total": len(cards)}), 200


# ── Admin: assign card to employee ─────────────────────────────

@rfid_bp.route("/assign", methods=["POST"])
@admin_required
def assign_card():
    """
    POST /api/v1/rfid/assign
    Body: { "card_uid": "A3:F2:89:1C", "employee_id": "uuid" }
    """
    data        = request.json or {}
    card_uid    = data.get("card_uid", "").strip().upper()
    employee_id = data.get("employee_id", "")

    if not card_uid or not employee_id:
        return jsonify({"error": "card_uid and employee_id required"}), 400

    # Check card exists in rfid_cards
    card = db.session.execute(text(
        "SELECT id FROM rfid_cards WHERE card_uid = :uid"
    ), {"uid": card_uid}).fetchone()

    if not card:
        return jsonify({"error": "Card not found in registry"}), 404

    # Check employee exists
    employee = Employee.query.filter_by(id=employee_id).first()
    if not employee:
        return jsonify({"error": "Employee not found"}), 404

    # Check card not already assigned to someone else
    if employee.card_uid and employee.card_uid != card_uid:
        return jsonify({
            "error": f"{employee.full_name} already has a card assigned ({employee.card_uid})"
        }), 400

    # Assign: update employee + mark card as assigned
    employee.card_uid = card_uid

    db.session.execute(text("""
        UPDATE rfid_cards
        SET is_assigned = TRUE, assigned_to = :emp_id
        WHERE card_uid = :uid
    """), {"emp_id": employee_id, "uid": card_uid})

    db.session.commit()

    logger.info(f"Card {card_uid} assigned to {employee.full_name}")
    return jsonify({
        "success":       True,
        "message":       f"Card {card_uid} assigned to {employee.full_name}",
        "employee_name": employee.full_name,
        "card_uid":      card_uid,
    }), 200


# ── Admin: delete / remove card from registry ──────────────────

@rfid_bp.route("/cards/<uuid:card_id>", methods=["DELETE"])
@admin_required
def delete_card(card_id):
    """DELETE /api/v1/rfid/cards/:id — remove from registry"""
    result = db.session.execute(text(
        "DELETE FROM rfid_cards WHERE id = :id AND is_assigned = FALSE RETURNING id"
    ), {"id": str(card_id)})
    db.session.commit()

    if not result.fetchone():
        return jsonify({"error": "Card not found or already assigned"}), 404

    return jsonify({"message": "Card removed from registry"}), 200


# ── Admin: unassign card from employee ─────────────────────────

@rfid_bp.route("/unassign", methods=["POST"])
@admin_required
def unassign_card():
    """
    POST /api/v1/rfid/unassign
    Body: { "employee_id": "uuid" }
    Removes card from employee — card returns to unassigned pool.
    """
    data        = request.json or {}
    employee_id = data.get("employee_id", "")

    employee = Employee.query.filter_by(id=employee_id).first()
    if not employee or not employee.card_uid:
        return jsonify({"error": "Employee not found or has no card"}), 404

    card_uid = employee.card_uid
    employee.card_uid = None

    db.session.execute(text("""
        UPDATE rfid_cards
        SET is_assigned = FALSE, assigned_to = NULL
        WHERE card_uid = :uid
    """), {"uid": card_uid})

    db.session.commit()
    logger.info(f"Card {card_uid} unassigned from {employee.full_name}")
    return jsonify({
        "success": True,
        "message": f"Card {card_uid} unassigned from {employee.full_name}",
    }), 200


# ── Legacy register endpoint (kept for compatibility) ──────────

@rfid_bp.route("/register", methods=["POST"])
@admin_required
def register_card_legacy():
    """Legacy: direct assign by card_uid + employee_id"""
    return assign_card()


# ── Scan mode (card registration preview) ─────────────────────

@rfid_bp.route("/scan-mode", methods=["POST"])
def scan_mode():
    if not _verify_key():
        return jsonify({"success": False}), 401
    data     = request.json or {}
    card_uid = data.get("card_uid", "").strip().upper()
    try:
        from app import socketio
        socketio.emit("rfid.card_scanned", {"card_uid": card_uid},
                      room="admin_dashboard")
    except Exception:
        pass
    return jsonify({"success": True, "card_uid": card_uid}), 200