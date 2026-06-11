"""
routes/socket_events.py — SocketIO event handlers
Handles: connect, disconnect, room joining for real-time attendance feed.
"""

from flask import request
from flask_socketio import join_room, leave_room, emit

from app import socketio
from utils.jwt_handler import JWTHandler
from utils.logger import get_logger

logger = get_logger(__name__)


@socketio.on("connect")
def handle_connect():
    """
    Client connects. Expects auth token in query string:
    ws://host/ws?token=<access_token>
    """
    token = request.args.get("token", "")
    payload = JWTHandler.decode_access_token(token)

    if not payload:
        logger.warning(f"WebSocket rejected — invalid token from {request.remote_addr}")
        return False  # Reject connection

    role = payload.get("role", "employee")
    user_id = payload.get("sub")

    # Join role-specific rooms
    if role in ("super_admin", "admin", "hr"):
        join_room("admin_dashboard")
        logger.info(f"Admin joined admin_dashboard room: {user_id}")

    # Always join personal room for user-specific notifications
    join_room(f"user_{user_id}")

    emit("connected", {
        "message": "Connected to AttendEase real-time service",
        "user_id": user_id,
        "role": role,
    })


@socketio.on("disconnect")
def handle_disconnect():
    logger.info(f"Client disconnected: {request.sid}")


@socketio.on("join_room")
def handle_join(data):
    """Allow client to join a specific room (e.g., department room)."""
    room = data.get("room")
    if room:
        join_room(room)
        emit("room_joined", {"room": room})


@socketio.on("ping")
def handle_ping():
    """Keepalive ping."""
    emit("pong", {"status": "ok"})
