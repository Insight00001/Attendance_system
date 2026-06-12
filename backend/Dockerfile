# AttendEase backend — one container per customer (Option A tenancy)
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SOCKETIO_ASYNC_MODE=eventlet

# System deps for psycopg2 and Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    gcc \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Lightweight requirements (no dlib/opencv — face clock-in runs on the
# kiosk machine, not in this container; RFID + dashboard fully work)
COPY requirements-render.txt .
RUN pip install --no-cache-dir -r requirements-render.txt

# Copy source
COPY . .

RUN mkdir -p uploads/photos uploads/snapshots logs

EXPOSE 5000

# wsgi.py runs idempotent schema init + admin seed on startup
CMD ["gunicorn", "--worker-class", "eventlet", "-w", "1", \
     "--bind", "0.0.0.0:5000", \
     "--timeout", "120", \
     "wsgi:app"]
