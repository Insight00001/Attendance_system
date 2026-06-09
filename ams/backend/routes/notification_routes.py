"""
routes/notification_routes.py
"""

from flask import Blueprint, request, jsonify, g
from services.notification_service import NotificationService
from middleware.auth_middleware import token_required

notification_bp = Blueprint("notifications", __name__)


@notification_bp.route("", methods=["GET"])
@token_required
def list_notifications():
    unread_only = request.args.get("unread_only", "false").lower() == "true"
    page = int(request.args.get("page", 1))
    result = NotificationService.get_user_notifications(
        str(g.current_user.id), unread_only=unread_only, page=page
    )
    return jsonify(result), 200


@notification_bp.route("/<uuid:notification_id>/read", methods=["PUT"])
@token_required
def mark_read(notification_id):
    success = NotificationService.mark_read(str(notification_id), str(g.current_user.id))
    if not success:
        return jsonify({"error": "Notification not found"}), 404
    return jsonify({"message": "Marked as read"}), 200


@notification_bp.route("/read-all", methods=["PUT"])
@token_required
def mark_all_read():
    count = NotificationService.mark_all_read(str(g.current_user.id))
    return jsonify({"message": f"{count} notifications marked as read"}), 200
