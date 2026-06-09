"""
routes/settings_routes.py — Settings endpoints
"""

import json
import os

from flask import Blueprint, request, jsonify, g

from middleware.auth_middleware import token_required, admin_required
from config.database import db
from models import User, Employee
from services.auth_service import AuthService
from utils.validators import validate_password_strength

settings_bp = Blueprint("settings", __name__)

SETTINGS_FILE = os.path.join(os.path.dirname(__file__), "..", "settings.json")


# ── Helpers ────────────────────────────────────────────────────

def load_settings() -> dict:
    defaults = {
        "company_name": "AttendEase",
        "company_logo": None,
        "default_shift_start": "08:00",
        "default_shift_end": "17:00",
        "default_late_threshold": 15,
        "timezone": "Africa/Lagos",
    }
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE) as f:
                defaults.update(json.load(f))
        except Exception:
            pass
    return defaults


def save_settings(data: dict):
    current = load_settings()
    current.update(data)
    with open(SETTINGS_FILE, "w") as f:
        json.dump(current, f, indent=2)


# ── GET settings ───────────────────────────────────────────────

@settings_bp.route("", methods=["GET"])
#@token_required
def get_settings():
    return jsonify(load_settings()), 200


# ── UPDATE company settings ────────────────────────────────────

@settings_bp.route("", methods=["PUT"])
@admin_required
def update_settings():
    data = request.json or {}
    allowed = {
        "company_name", "default_shift_start",
        "default_shift_end", "default_late_threshold", "timezone",
    }
    filtered = {k: v for k, v in data.items() if k in allowed}
    if not filtered:
        return jsonify({"error": "No valid settings provided"}), 400
    save_settings(filtered)
    return jsonify({"message": "Settings updated", "settings": load_settings()}), 200


# ── Update profile ─────────────────────────────────────────────

@settings_bp.route("/profile", methods=["PUT"])
@token_required
def update_profile():
    data = request.json or {}
    user = g.current_user
    if not user.employee:
        return jsonify({"error": "No employee record found"}), 404
    if "first_name" in data:
        user.employee.first_name = data["first_name"].strip()
    if "last_name" in data:
        user.employee.last_name = data["last_name"].strip()
    if "phone" in data:
        user.employee.phone = data["phone"].strip()
    db.session.commit()
    return jsonify({
        "message": "Profile updated",
        "employee": user.employee.to_dict(),
    }), 200


# ── Change password ────────────────────────────────────────────

@settings_bp.route("/change-password", methods=["PUT"])
@token_required
def change_password():
    data = request.json or {}
    current_password = data.get("current_password", "")
    new_password     = data.get("new_password", "")
    if not current_password or not new_password:
        return jsonify({"error": "current_password and new_password required"}), 400
    if not AuthService.verify_password(current_password, g.current_user.password_hash):
        return jsonify({"error": "Current password is incorrect"}), 400
    error = validate_password_strength(new_password)
    if error:
        return jsonify({"error": error}), 400
    g.current_user.password_hash = AuthService.hash_password(new_password)
    db.session.commit()
    return jsonify({"message": "Password changed successfully"}), 200


# ── Update shift ───────────────────────────────────────────────

@settings_bp.route("/shift", methods=["PUT"])
@admin_required
def update_default_shift():
    data           = request.json or {}
    shift_start    = data.get("shift_start")
    shift_end      = data.get("shift_end")
    late_threshold = data.get("late_threshold")
    employee_id    = data.get("employee_id")

    if not any([shift_start, shift_end, late_threshold]):
        return jsonify({"error": "Provide shift_start, shift_end, or late_threshold"}), 400

    query = Employee.query.filter_by(employment_status="active")
    if employee_id:
        query = query.filter_by(id=employee_id)

    updated = 0
    for emp in query.all():
        if shift_start:
            emp.shift_start = shift_start
        if shift_end:
            emp.shift_end = shift_end
        if late_threshold is not None:
            emp.late_threshold = int(late_threshold)
        updated += 1

    save_settings({k: v for k, v in {
        "default_shift_start":    shift_start,
        "default_shift_end":      shift_end,
        "default_late_threshold": late_threshold,
    }.items() if v is not None})

    db.session.commit()
    return jsonify({
        "message": f"Shift updated for {updated} employee(s)",
        "shift_start": shift_start,
        "shift_end":   shift_end,
    }), 200


# ── Departments ────────────────────────────────────────────────

@settings_bp.route("/departments", methods=["GET"])
@token_required
def list_departments():
    from models import Department
    depts = Department.query.filter_by(is_active=True).order_by(Department.name).all()
    return jsonify([d.to_dict() for d in depts]), 200


@settings_bp.route("/departments", methods=["POST"])
@admin_required
def create_department():
    from models import Department
    data = request.json or {}
    name = data.get("name", "").strip()
    code = data.get("code", "").strip().upper()
    if not name or not code:
        return jsonify({"error": "name and code required"}), 400
    if Department.query.filter_by(name=name).first():
        return jsonify({"error": f"Department '{name}' already exists"}), 400
    dept = Department(name=name, code=code, description=data.get("description", ""))
    db.session.add(dept)
    db.session.commit()
    return jsonify({"message": "Department created", "department": dept.to_dict()}), 201


@settings_bp.route("/departments/<uuid:dept_id>", methods=["DELETE"])
@admin_required
def delete_department(dept_id):
    from models import Department
    dept = Department.query.filter_by(id=str(dept_id)).first()
    if not dept:
        return jsonify({"error": "Department not found"}), 404
    dept.is_active = False
    db.session.commit()
    return jsonify({"message": "Department removed"}), 200


# ── Roles ──────────────────────────────────────────────────────

@settings_bp.route("/roles", methods=["GET"])
@token_required
def list_roles():
    from models import Role
    roles = Role.query.filter_by(is_active=True).order_by(Role.name).all()
    return jsonify([r.to_dict() for r in roles]), 200


@settings_bp.route("/roles", methods=["POST"])
@admin_required
def create_role():
    from models import Role
    data = request.json or {}
    name = data.get("name", "").strip()
    code = data.get("code", "").strip().upper()
    if not name or not code:
        return jsonify({"error": "name and code required"}), 400
    if Role.query.filter_by(name=name).first():
        return jsonify({"error": f"Role '{name}' already exists"}), 400
    role = Role(name=name, code=code, description=data.get("description", ""))
    db.session.add(role)
    db.session.commit()
    return jsonify({"message": "Role created", "role": role.to_dict()}), 201


@settings_bp.route("/roles/<uuid:role_id>", methods=["DELETE"])
@admin_required
def delete_role(role_id):
    from models import Role
    role = Role.query.filter_by(id=str(role_id)).first()
    if not role:
        return jsonify({"error": "Role not found"}), 404
    role.is_active = False
    db.session.commit()
    return jsonify({"message": "Role removed"}), 200