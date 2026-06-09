"""
routes/auth_routes.py — Authentication endpoints
"""

from flask import Blueprint, request, jsonify, g
from marshmallow import Schema, fields, validate, ValidationError

from services.auth_service import AuthService
from middleware.auth_middleware import token_required
from middleware.rate_limiter import limiter

auth_bp = Blueprint("auth", __name__)


# ── Validation Schemas ─────────────────────────────────────────

class LoginSchema(Schema):
    email    = fields.Email(required=True)
    password = fields.Str(required=True, validate=validate.Length(min=6))

class ResetRequestSchema(Schema):
    email = fields.Email(required=True)

class ResetPasswordSchema(Schema):
    token    = fields.Str(required=True)
    password = fields.Str(required=True, validate=validate.Length(min=8))


# ── Routes ────────────────────────────────────────────────────

@auth_bp.route("/login", methods=["POST"])
@limiter.limit("10 per minute")
def login():
    """POST /api/v1/auth/login"""
    try:
        data = LoginSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": "Validation failed", "details": e.messages}), 422

    device_info = {
        "ip": request.remote_addr,
        "user_agent": request.user_agent.string,
    }

    result, error = AuthService.login(data["email"], data["password"], device_info)
    if error:
        return jsonify({"error": error}), 401

    return jsonify(result), 200


@auth_bp.route("/refresh", methods=["POST"])
def refresh():
    """POST /api/v1/auth/refresh — exchange refresh token"""
    body = request.json or {}
    refresh_token = body.get("refresh_token", "")
    if not refresh_token:
        return jsonify({"error": "refresh_token required"}), 400

    result, error = AuthService.refresh_tokens(refresh_token)
    if error:
        return jsonify({"error": error}), 401

    return jsonify(result), 200


@auth_bp.route("/logout", methods=["POST"])
@token_required
def logout():
    """POST /api/v1/auth/logout"""
    body = request.json or {}
    refresh_token = body.get("refresh_token", "")
    AuthService.logout(refresh_token)
    return jsonify({"message": "Logged out successfully"}), 200


@auth_bp.route("/me", methods=["GET"])
@token_required
def me():
    """GET /api/v1/auth/me — current user profile"""
    user = g.current_user
    data = user.to_dict()
    if user.employee:
        data["employee"] = user.employee.to_dict(include_sensitive=True)
    return jsonify(data), 200


@auth_bp.route("/forgot-password", methods=["POST"])
@limiter.limit("5 per minute")
def forgot_password():
    """POST /api/v1/auth/forgot-password"""
    try:
        data = ResetRequestSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    token, _ = AuthService.initiate_password_reset(data["email"])

    # In production, email the token — here we return it for dev convenience
    # NotificationService.send_reset_email(data["email"], token)
    return jsonify({"message": "If the email exists, a reset link has been sent."}), 200


@auth_bp.route("/reset-password", methods=["POST"])
def reset_password():
    """POST /api/v1/auth/reset-password"""
    try:
        data = ResetPasswordSchema().load(request.json or {})
    except ValidationError as e:
        return jsonify({"error": e.messages}), 422

    success, error = AuthService.complete_password_reset(data["token"], data["password"])
    if not success:
        return jsonify({"error": error}), 400

    return jsonify({"message": "Password reset successfully"}), 200
