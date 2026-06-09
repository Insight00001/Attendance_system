"""
middleware/auth_middleware.py
JWT authentication decorators for Flask routes.
"""

from functools import wraps
from flask import request, jsonify, g
from utils.jwt_handler import JWTHandler
from models import User


def token_required(f):
    """
    Decorator: validates JWT access token from Authorization header.
    Sets g.current_user on success.

    Usage:
        @auth_bp.route('/me')
        @token_required
        def get_me():
            return jsonify(g.current_user.to_dict())
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid Authorization header"}), 401

        token = auth_header.split(" ", 1)[1]
        payload = JWTHandler.decode_access_token(token)

        if not payload:
            return jsonify({"error": "Token is invalid or expired"}), 401

        user = User.query.filter_by(id=payload["sub"], is_active=True).first()
        if not user:
            return jsonify({"error": "User not found or deactivated"}), 401

        if user.is_locked():
            return jsonify({"error": "Account is temporarily locked"}), 403

        g.current_user = user
        g.token_payload = payload
        return f(*args, **kwargs)

    return decorated


def admin_required(f):
    """
    Decorator: requires token_required + admin/hr/super_admin role.
    Must be used AFTER @token_required or standalone (includes token check).
    """
    @wraps(f)
    @token_required
    def decorated(*args, **kwargs):
        if not g.current_user.is_admin():
            return jsonify({"error": "Admin access required"}), 403
        return f(*args, **kwargs)

    return decorated


def super_admin_required(f):
    """Only super_admin role allowed."""
    @wraps(f)
    @token_required
    def decorated(*args, **kwargs):
        if g.current_user.user_role != "super_admin":
            return jsonify({"error": "Super admin access required"}), 403
        return f(*args, **kwargs)

    return decorated


def self_or_admin(f):
    """
    Allows access if the requesting user IS the employee or is an admin.
    Expects `employee_id` in URL kwargs.
    """
    @wraps(f)
    @token_required
    def decorated(*args, **kwargs):
        from models import Employee
        emp_id = kwargs.get("employee_id")
        user = g.current_user

        if user.is_admin():
            return f(*args, **kwargs)

        # Check if user owns this employee record
        employee = Employee.query.filter_by(id=emp_id, user_id=user.id).first()
        if not employee:
            return jsonify({"error": "Access denied"}), 403

        return f(*args, **kwargs)

    return decorated
