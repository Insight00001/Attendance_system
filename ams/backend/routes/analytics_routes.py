from datetime import date, timedelta
from flask import Blueprint, request, jsonify
from sqlalchemy import text

from middleware.auth_middleware import admin_required
from config.database import db
from utils.logger import get_logger

analytics_bp = Blueprint("analytics", __name__)
logger       = get_logger(__name__)


# ── Dashboard Summary ──────────────────────────────────────────

@analytics_bp.route("/summary", methods=["GET"])
@admin_required
def summary():
    """GET /api/v1/analytics/summary — today's attendance summary"""
    today = date.today()

    try:
        # Total active employees
        total = db.session.execute(text("""
            SELECT COUNT(*) FROM employees
            WHERE employment_status = 'active'
        """)).scalar() or 0

        # Today's stats
        stats = db.session.execute(text("""
            SELECT
                COUNT(*) FILTER (WHERE status = 'present') AS present,
                COUNT(*) FILTER (WHERE status = 'late')    AS late,
                COUNT(*) FILTER (WHERE status = 'absent')  AS absent,
                COUNT(*) FILTER (WHERE status = 'on_leave') AS on_leave
            FROM attendance_logs
            WHERE attendance_date = :today
        """), {"today": today}).fetchone()

        present  = stats.present  if stats else 0
        late     = stats.late     if stats else 0
        absent   = stats.absent   if stats else 0
        on_leave = stats.on_leave if stats else 0

        # Employees not yet clocked in = total - (present + late + on_leave)
        not_clocked = max(0, total - present - late - on_leave)

        attendance_rate = round((present + late) / total * 100, 1) if total > 0 else 0

        return jsonify({
            "total_employees":  total,
            "present":          present,
            "late":             late,
            "absent":           not_clocked,
            "on_leave":         on_leave,
            "attendance_rate":  attendance_rate,
            "date":             today.isoformat(),
        }), 200

    except Exception as e:
        logger.error(f"Summary error: {e}")
        return jsonify({
            "total_employees": 0,
            "present":         0,
            "late":            0,
            "absent":          0,
            "on_leave":        0,
            "attendance_rate": 0,
            "date":            today.isoformat(),
        }), 200


# ── 30-day Attendance Trend ────────────────────────────────────

@analytics_bp.route("/trend", methods=["GET"])
@admin_required
def trend():
    """GET /api/v1/analytics/trend — daily present/absent for last 30 days"""
    days = int(request.args.get("days", 30))
    end_date   = date.today()
    start_date = end_date - timedelta(days=days - 1)

    try:
        rows = db.session.execute(text("""
            SELECT
                attendance_date,
                COUNT(*) FILTER (WHERE status IN ('present','late')) AS present,
                COUNT(*) FILTER (WHERE status = 'absent')            AS absent,
                COUNT(*) FILTER (WHERE status = 'late')              AS late,
                COUNT(*) FILTER (WHERE status = 'on_leave')          AS on_leave
            FROM attendance_logs
            WHERE attendance_date BETWEEN :start AND :end
            GROUP BY attendance_date
            ORDER BY attendance_date ASC
        """), {"start": start_date, "end": end_date}).fetchall()

        # Build a map so we can fill in missing days with zeros
        # Total active employees (for rate calculation)
        total_employees = db.session.execute(text(
            "SELECT COUNT(*) FROM employees WHERE employment_status = 'active'"
        )).scalar() or 1  # avoid div-by-zero

        data_map = {}
        for row in rows:
            d = dict(row._mapping)
            present = int(d["present"] or 0)
            absent  = int(d["absent"]  or 0)
            late    = int(d["late"]    or 0)
            rate    = round((present) / total_employees * 100, 1)
            data_map[str(d["attendance_date"])] = {
                "date":            str(d["attendance_date"]),
                "present":         present,
                "absent":          absent,
                "late":            late,
                "on_leave":        int(d["on_leave"] or 0),
                "attendance_rate": rate,
            }

        # Fill missing days with zeros
        trend_data = []
        current = start_date
        while current <= end_date:
            key = str(current)
            trend_data.append(data_map.get(key, {
                "date":            key,
                "present":         0,
                "absent":          0,
                "late":            0,
                "on_leave":        0,
                "attendance_rate": 0,
            }))
            current += timedelta(days=1)

        return jsonify({
            "trend":      trend_data,
            "start_date": str(start_date),
            "end_date":   str(end_date),
            "days":       days,
        }), 200

    except Exception as e:
        logger.error(f"Trend error: {e}")
        return jsonify({
            "trend":      [],
            "start_date": str(start_date),
            "end_date":   str(end_date),
            "days":       days,
        }), 200


# ── Department Breakdown ───────────────────────────────────────

@analytics_bp.route("/departments", methods=["GET"])
@admin_required
def department_stats():
    """GET /api/v1/analytics/departments"""
    today = date.today()

    try:
        rows = db.session.execute(text("""
            SELECT
                d.name AS department,
                COUNT(DISTINCT e.id)                                              AS total,
                COUNT(al.id) FILTER (WHERE al.status IN ('present','late'))       AS present,
                COUNT(al.id) FILTER (WHERE al.status = 'late')                    AS late,
                COUNT(al.id) FILTER (WHERE al.status = 'absent')                  AS absent
            FROM departments d
            JOIN employees e ON e.department_id = d.id
                AND e.employment_status = 'active'
            LEFT JOIN attendance_logs al ON al.employee_id = e.id
                AND al.attendance_date = :today
            WHERE d.is_active = TRUE
            GROUP BY d.name
            ORDER BY d.name
        """), {"today": today}).fetchall()

        departments = []
        for row in rows:
            d = dict(row._mapping)
            total = int(d["total"] or 0)
            present = int(d["present"] or 0)
            departments.append({
                "department":      d["department"],
                "total":           total,
                "present":         present,
                "late":            int(d["late"]   or 0),
                "absent":          int(d["absent"] or 0),
                "attendance_rate": round(present / total * 100, 1) if total > 0 else 0,
            })

        return jsonify({"departments": departments}), 200

    except Exception as e:
        logger.error(f"Department stats error: {e}")
        return jsonify({"departments": []}), 200


# ── Late Arrivals Report ───────────────────────────────────────

@analytics_bp.route("/late-report", methods=["GET"])
@admin_required
def late_report():
    """GET /api/v1/analytics/late-report?days=30"""
    days       = int(request.args.get("days", 30))
    end_date   = date.today()
    start_date = end_date - timedelta(days=days - 1)

    try:
        rows = db.session.execute(text("""
            SELECT
                e.employee_id,
                e.first_name || ' ' || e.last_name AS name,
                d.name AS department,
                COUNT(*) AS late_count,
                AVG(al.late_minutes) AS avg_late_minutes
            FROM attendance_logs al
            JOIN employees e  ON al.employee_id = e.id
            LEFT JOIN departments d ON e.department_id = d.id
            WHERE al.status = 'late'
              AND al.attendance_date BETWEEN :start AND :end
            GROUP BY e.employee_id, e.first_name, e.last_name, d.name
            ORDER BY late_count DESC
            LIMIT 20
        """), {"start": start_date, "end": end_date}).fetchall()

        report = []
        for row in rows:
            d = dict(row._mapping)
            report.append({
                "employee_id":      d["employee_id"],
                "name":             d["name"],
                "department":       d["department"],
                "late_count":       int(d["late_count"] or 0),
                "avg_late_minutes": round(float(d["avg_late_minutes"] or 0), 1),
            })

        return jsonify({
            "report":     report,
            "start_date": str(start_date),
            "end_date":   str(end_date),
            "days":       days,
        }), 200

    except Exception as e:
        logger.error(f"Late report error: {e}")
        return jsonify({"report": [], "days": days}), 200


# ── Overtime Report ────────────────────────────────────────────

@analytics_bp.route("/overtime", methods=["GET"])
@admin_required
def overtime_report():
    """GET /api/v1/analytics/overtime?days=30"""
    days       = int(request.args.get("days", 30))
    end_date   = date.today()
    start_date = end_date - timedelta(days=days - 1)

    try:
        rows = db.session.execute(text("""
            SELECT
                e.employee_id,
                e.first_name || ' ' || e.last_name AS name,
                SUM(al.overtime_minutes)  AS total_overtime_minutes,
                SUM(al.working_minutes)   AS total_working_minutes,
                COUNT(*) AS days_worked
            FROM attendance_logs al
            JOIN employees e ON al.employee_id = e.id
            WHERE al.attendance_date BETWEEN :start AND :end
              AND al.overtime_minutes > 0
            GROUP BY e.employee_id, e.first_name, e.last_name
            ORDER BY total_overtime_minutes DESC
            LIMIT 20
        """), {"start": start_date, "end": end_date}).fetchall()

        report = []
        for row in rows:
            d = dict(row._mapping)
            report.append({
                "employee_id":           d["employee_id"],
                "name":                  d["name"],
                "total_overtime_minutes": int(d["total_overtime_minutes"] or 0),
                "total_working_minutes":  int(d["total_working_minutes"] or 0),
                "days_worked":            int(d["days_worked"] or 0),
            })

        return jsonify({
            "report":     report,
            "start_date": str(start_date),
            "end_date":   str(end_date),
        }), 200

    except Exception as e:
        logger.error(f"Overtime error: {e}")
        return jsonify({"report": []}), 200