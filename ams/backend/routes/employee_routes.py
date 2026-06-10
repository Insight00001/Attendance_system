from flask import Blueprint, request, jsonify, g
from marshmallow import Schema, fields, validate, ValidationError

from services.employee_service import EmployeeService
from middleware.auth_middleware import token_required, admin_required
from models import Employee, Department, Role

employee_bp = Blueprint("employees", __name__)


# ── Validation Schema ──────────────────────────────────────────

class CreateEmployeeSchema(Schema):
    email          = fields.Email(required=True)
    password       = fields.Str(load_default=None)
    first_name     = fields.Str(required=True, validate=validate.Length(min=1, max=100))
    last_name      = fields.Str(required=True, validate=validate.Length(min=1, max=100))
    middle_name    = fields.Str(load_default="")
    gender         = fields.Str(load_default="prefer_not_to_say")
    phone          = fields.Str(load_default=None)
    address        = fields.Str(load_default=None)
    department_id  = fields.UUID(load_default=None)
    role_id        = fields.UUID(load_default=None)
    job_title      = fields.Str(load_default=None)
    hire_date      = fields.Date(load_default=None)
    shift_start    = fields.Time(load_default=None)
    shift_end      = fields.Time(load_default=None)
    late_threshold = fields.Int(load_default=15, validate=validate.Range(0, 120))
    user_role      = fields.Str(load_default="employee",
                                validate=validate.OneOf(["employee", "admin", "hr"]))


# ── List employees (public — needed before login for dropdowns) ─

@employee_bp.route("", methods=["GET"])
@token_required
def list_employees():
    """GET /api/v1/employees"""
    result = EmployeeService.search_employees(
        query=request.args.get("query"),
        department_id=request.args.get("department_id"),
        status=request.args.get("status", "active"),
        page=int(request.args.get("page", 1)),
        per_page=int(request.args.get("per_page", 20)),
    )
    return jsonify(result), 200


# ── Get single employee ────────────────────────────────────────

@employee_bp.route("/<uuid:employee_id>", methods=["GET"])
@token_required
def get_employee(employee_id):
    """GET /api/v1/employees/:id"""
    employee = Employee.query.filter_by(id=str(employee_id)).first()
    if not employee:
        return jsonify({"error": "Employee not found"}), 404

    include_sensitive = (
        g.current_user.is_admin() or
        str(employee.user_id) == str(g.current_user.id)
    )
    return jsonify(employee.to_dict(include_sensitive=include_sensitive)), 200


# ── Create employee ────────────────────────────────────────────

@employee_bp.route("", methods=["POST"])
@admin_required
def create_employee():
    """POST /api/v1/employees"""
    try:
        if request.content_type and "multipart" in request.content_type:
            raw = request.form.to_dict()
        else:
            raw = request.json or {}
        data = CreateEmployeeSchema().load(raw)
    except ValidationError as e:
        return jsonify({"error": "Validation failed", "details": e.messages}), 422

    photo = request.files.get("photo")
    employee, error = EmployeeService.create_employee(
        data=data,
        photo=photo,
        created_by_id=str(g.current_user.id),
    )
    if error:
        return jsonify({"error": error}), 400

    return jsonify({"message": "Employee created", "employee": employee.to_dict()}), 201


# ── Update employee (PUT = JSON, POST multipart = with photo) ──

@employee_bp.route("/<uuid:employee_id>", methods=["PUT", "POST"])
@admin_required
def update_employee(employee_id):
    """PUT /api/v1/employees/:id  or  POST multipart with photo"""
    if request.content_type and "multipart" in request.content_type:
        data = request.form.to_dict()
    else:
        data = request.json or {}

    # Convert numeric strings from form data
    if "late_threshold" in data:
        try:
            data["late_threshold"] = int(data["late_threshold"])
        except (ValueError, TypeError):
            pass

    photo = request.files.get("photo")
    employee, error = EmployeeService.update_employee(str(employee_id), data, photo)
    if error:
        return jsonify({"error": error}), 400

    return jsonify({"message": "Employee updated", "employee": employee.to_dict()}), 200


# ── Delete employee ────────────────────────────────────────────

@employee_bp.route("/<uuid:employee_id>", methods=["DELETE"])
@admin_required
def delete_employee(employee_id):
    """DELETE /api/v1/employees/:id?hard=true"""
    hard = request.args.get("hard", "true").lower() == "true"
    success, error = EmployeeService.deactivate_employee(str(employee_id), hard_delete=hard)
    if not success:
        return jsonify({"error": error}), 404
    return jsonify({"message": "Employee deleted successfully"}), 200


# ── Upload / update photo ──────────────────────────────────────

@employee_bp.route("/<uuid:employee_id>/photo", methods=["POST"])
@admin_required
def upload_photo(employee_id):
    """POST /api/v1/employees/:id/photo"""
    photo = request.files.get("photo")
    if not photo:
        return jsonify({"error": "photo file required"}), 400

    employee = Employee.query.filter_by(id=str(employee_id)).first()
    if not employee:
        return jsonify({"error": "Employee not found"}), 404

    photo_url, err = EmployeeService.save_employee_photo(photo)
    if err:
        return jsonify({"error": err}), 400

    employee.photo_url = photo_url

    from config.database import db
    db.session.commit()

    return jsonify({"message": "Photo updated", "photo_url": photo_url}), 200


# ── Employee attendance history ────────────────────────────────

@employee_bp.route("/<uuid:employee_id>/attendance", methods=["GET"])
@token_required
def employee_attendance(employee_id):
    """GET /api/v1/employees/:id/attendance"""
    from services.attendance_service import AttendanceService
    from datetime import date

    start = request.args.get("start_date")
    end   = request.args.get("end_date")

    result = AttendanceService.get_attendance_logs(
        employee_id=str(employee_id),
        start_date=date.fromisoformat(start) if start else None,
        end_date=date.fromisoformat(end) if end else None,
        page=int(request.args.get("page", 1)),
    )
    return jsonify(result), 200


# ── Departments (public) ───────────────────────────────────────

@employee_bp.route("/departments", methods=["GET"])
def list_departments():
    """GET /api/v1/employees/departments — public"""
    depts = Department.query.filter_by(is_active=True).all()
    return jsonify([d.to_dict() for d in depts]), 200


# ── Roles (public) ─────────────────────────────────────────────

@employee_bp.route("/roles", methods=["GET"])
def list_roles():
    """GET /api/v1/employees/roles — public"""
    roles = Role.query.filter_by(is_active=True).all()
    return jsonify([r.to_dict() for r in roles]), 200