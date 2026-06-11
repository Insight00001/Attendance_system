"""WSGI entry point for Gunicorn."""
import os

# On cloud deploys (Render) we run gunicorn with the eventlet worker so
# Socket.IO gets real WebSockets. Eventlet must monkey-patch the stdlib
# BEFORE anything else is imported.
if os.getenv("SOCKETIO_ASYNC_MODE") == "eventlet":
    import eventlet
    eventlet.monkey_patch()

from app import create_app, socketio

app = create_app()

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=5000, debug=False)
