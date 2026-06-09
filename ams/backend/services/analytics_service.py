"""
services/analytics_service.py — Dashboard analytics and reports
"""

from datetime import date, datetime, timedelta
from typing import Optional
from sqlalchemy import func, and_, case

from config.database import db
from models import Employee, AttendanceLog, Department


class AnalyticsService:
    """Generates aggregated statistics for the admin dashboard."""

    # ── Dashboard Summary ─────────────────────────────────────

    @staticmethod
    def get_summary(target_date: Optional[date] = None) -> dict:
        """
        High-level daily summary.
        Returns: total_employees, present, absent, late, on_leave, avg_working_hours
        """
        target_date = target_date or date.today()

        total_active = Employee.query.filter_by(employment_status="active").count()

        # Today's attendance data
        day_logs = AttendanceLog.query.filter_by(attendance_date=target_date).all()

        clocked_in = [l for l in day_logs if l.clock_in]
        late_arrivals = [l for l in clocked_in if l.is_late]
        clocked_out = [l for l in day_logs if l.clock_out]

        total_working = sum(l.working_minutes for l in clocked_out if l.working_minutes)
        avg_working = (total_working / len(clocked_out)) if clocked_out else 0

        return {
            "date": target_date.isoformat(),
            "total_employees": total_active,
            "present": len(clocked_in),
            "absent": total_active - len(clocked_in),
            "late": len(late_arrivals),
            "clocked_out": len(clocked_out),
            "still_in_office": len(clocked_in) - len(clocked_out),
            "attendance_rate": round(len(clocked_in) / total_active * 100, 1) if total_active else 0,
            "avg_working_minutes": round(avg_working, 0),
        }

    # ── Daily Trend (Last N Days) ──────────────────────────────

    @staticmethod
    def get_daily_trend(days: int = 30) -> list:
        """
        Attendance trend for the last N days.
        Returns list of { date, present, absent, late }
        """
        end_date = date.today()
        start_date = end_date - timedelta(days=days - 1)

        # Aggregate per date
        rows = (
            db.session.query(
                AttendanceLog.attendance_date,
                func.count(AttendanceLog.id).label("present"),
                func.sum(case((AttendanceLog.is_late == True, 1), else_=0)).label("late"),
            )
            .filter(
                AttendanceLog.attendance_date.between(start_date, end_date),
                AttendanceLog.clock_in.isnot(None),
            )
            .group_by(AttendanceLog.attendance_date)
            .order_by(AttendanceLog.attendance_date)
            .all()
        )

        total_active = Employee.query.filter_by(employment_status="active").count()

        trend = []
        for row in rows:
            trend.append({
                "date": row.attendance_date.isoformat(),
                "present": row.present,
                "absent": total_active - row.present,
                "late": row.late,
                "attendance_rate": round(row.present / total_active * 100, 1) if total_active else 0,
            })

        return trend

    # ── Per Department ────────────────────────────────────────

    @staticmethod
    def get_department_stats(target_date: Optional[date] = None) -> list:
        """Attendance breakdown by department for a given date."""
        target_date = target_date or date.today()

        depts = Department.query.filter_by(is_active=True).all()
        result = []

        for dept in depts:
            total = Employee.query.filter_by(
                department_id=dept.id, employment_status="active"
            ).count()
            if total == 0:
                continue

            present = (
                db.session.query(func.count(AttendanceLog.id))
                .join(Employee, AttendanceLog.employee_id == Employee.id)
                .filter(
                    Employee.department_id == dept.id,
                    AttendanceLog.attendance_date == target_date,
                    AttendanceLog.clock_in.isnot(None),
                )
                .scalar()
            )

            result.append({
                "department": dept.name,
                "department_code": dept.code,
                "total": total,
                "present": present,
                "absent": total - present,
                "attendance_rate": round(present / total * 100, 1),
            })

        return sorted(result, key=lambda x: x["attendance_rate"], reverse=True)

    # ── Late Arrival Report ───────────────────────────────────

    @staticmethod
    def get_late_arrivals_report(
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        top_n: int = 20,
    ) -> list:
        """Top N most chronically late employees."""
        start_date = start_date or (date.today() - timedelta(days=30))
        end_date = end_date or date.today()

        rows = (
            db.session.query(
                Employee.employee_id,
                (Employee.first_name + " " + Employee.last_name).label("full_name"),
                func.count(AttendanceLog.id).label("late_count"),
                func.avg(AttendanceLog.late_minutes).label("avg_late_minutes"),
                func.max(AttendanceLog.late_minutes).label("max_late_minutes"),
            )
            .join(AttendanceLog, AttendanceLog.employee_id == Employee.id)
            .filter(
                AttendanceLog.is_late == True,
                AttendanceLog.attendance_date.between(start_date, end_date),
            )
            .group_by(Employee.id)
            .order_by(func.count(AttendanceLog.id).desc())
            .limit(top_n)
            .all()
        )

        return [
            {
                "employee_id": r.employee_id,
                "full_name": r.full_name,
                "late_days": r.late_count,
                "avg_late_minutes": round(float(r.avg_late_minutes or 0), 1),
                "max_late_minutes": r.max_late_minutes or 0,
            }
            for r in rows
        ]

    # ── Overtime Report ───────────────────────────────────────

    @staticmethod
    def get_overtime_report(
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
    ) -> list:
        """Employees with most overtime in date range."""
        start_date = start_date or (date.today() - timedelta(days=30))
        end_date = end_date or date.today()

        rows = (
            db.session.query(
                Employee.employee_id,
                (Employee.first_name + " " + Employee.last_name).label("full_name"),
                func.sum(AttendanceLog.overtime_minutes).label("total_overtime"),
                func.count(AttendanceLog.id).label("days_worked"),
            )
            .join(AttendanceLog, AttendanceLog.employee_id == Employee.id)
            .filter(
                AttendanceLog.overtime_minutes > 0,
                AttendanceLog.attendance_date.between(start_date, end_date),
            )
            .group_by(Employee.id)
            .order_by(func.sum(AttendanceLog.overtime_minutes).desc())
            .all()
        )

        return [
            {
                "employee_id": r.employee_id,
                "full_name": r.full_name,
                "total_overtime_minutes": r.total_overtime or 0,
                "total_overtime_hours": round((r.total_overtime or 0) / 60, 1),
                "days_worked": r.days_worked,
            }
            for r in rows
        ]
