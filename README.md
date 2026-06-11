# 🏢 AttendEase — Employee Attendance Management System

A production-ready, full-stack Employee Attendance Management System with facial recognition,
real-time monitoring, and role-based dashboards.

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter Frontend                       │
│         (Mobile + Desktop Responsive)                     │
│   Admin Dashboard | Employee App | Camera Attendance      │
└────────────────────┬────────────────────────────────────┘
                     │ REST API + WebSocket
┌────────────────────▼────────────────────────────────────┐
│                  Flask Backend                            │
│  Auth │ Employee │ Attendance │ Analytics │ Notify       │
│  Face Recognition Service (OpenCV + face_recognition)    │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              PostgreSQL Database                          │
│  users │ employees │ attendance_logs │ face_encodings    │
└─────────────────────────────────────────────────────────┘
```

---

## 🗂️ Project Structure

```
ams/
├── README.md
├── docker-compose.yml
├── database/
│   ├── schema.sql                  # Full PostgreSQL schema
│   └── migrations/
│       └── 001_initial.sql
├── backend/
│   ├── app.py                      # Flask app entry point
│   ├── requirements.txt
│   ├── .env.example
│   ├── wsgi.py                     # Gunicorn WSGI entry
│   ├── config/
│   │   ├── config.py               # App configuration
│   │   └── database.py             # DB connection + pool
│   ├── models/
│   │   ├── user.py
│   │   ├── employee.py
│   │   ├── department.py
│   │   ├── role.py
│   │   ├── attendance.py
│   │   ├── face_encoding.py
│   │   ├── notification.py
│   │   └── session.py
│   ├── routes/
│   │   ├── auth_routes.py
│   │   ├── employee_routes.py
│   │   ├── attendance_routes.py
│   │   ├── analytics_routes.py
│   │   └── notification_routes.py
│   ├── controllers/
│   │   ├── auth_controller.py
│   │   ├── employee_controller.py
│   │   ├── attendance_controller.py
│   │   ├── analytics_controller.py
│   │   └── notification_controller.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── employee_service.py
│   │   ├── face_recognition_service.py
│   │   ├── attendance_service.py
│   │   └── notification_service.py
│   ├── repositories/
│   │   ├── user_repository.py
│   │   ├── employee_repository.py
│   │   └── attendance_repository.py
│   ├── middleware/
│   │   ├── auth_middleware.py
│   │   ├── rate_limiter.py
│   │   └── error_handler.py
│   ├── utils/
│   │   ├── validators.py
│   │   ├── helpers.py
│   │   ├── logger.py
│   │   └── jwt_handler.py
│   └── tests/
│       ├── test_auth.py
│       ├── test_employee.py
│       └── test_attendance.py
├── flutter_app/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── config/
│   │   │   ├── app_config.dart
│   │   │   └── routes.dart
│   │   ├── models/
│   │   │   ├── user_model.dart
│   │   │   ├── employee_model.dart
│   │   │   └── attendance_model.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   ├── auth_service.dart
│   │   │   ├── attendance_service.dart
│   │   │   └── websocket_service.dart
│   │   ├── bloc/
│   │   │   ├── auth/
│   │   │   ├── attendance/
│   │   │   └── employee/
│   │   ├── screens/
│   │   │   ├── auth/login_screen.dart
│   │   │   ├── admin/admin_dashboard.dart
│   │   │   ├── employee/employee_dashboard.dart
│   │   │   └── attendance/camera_attendance_screen.dart
│   │   ├── widgets/
│   │   ├── themes/
│   │   │   └── app_theme.dart
│   │   └── utils/
│   └── test/
└── docker/
    ├── backend.Dockerfile
    └── nginx.conf
```

---

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose
- Python 3.10+
- Flutter 3.x SDK
- PostgreSQL 15+

### 1. Clone and Configure

```bash
git clone <repo-url>
cd ams
cp backend/.env.example backend/.env
# Edit .env with your values
```

### 2. Start with Docker

```bash
docker-compose up --build
```

This starts:
- PostgreSQL on port 5432
- Flask backend on port 5000
- Nginx reverse proxy on port 80

### 3. Run Database Migrations

```bash
docker-compose exec backend python -m flask db upgrade
# Or manually:
psql -U postgres -d attendease -f database/schema.sql
```

### 4. Create Admin User

```bash
docker-compose exec backend python -c "
from services.auth_service import AuthService
AuthService.create_admin('admin@company.com', 'Admin@1234', 'System Admin')
"
```

### 5. Flutter Setup

```bash
cd flutter_app
flutter pub get
# For mobile:
flutter run
# For desktop:
flutter run -d windows  # or macos / linux
```

---

## 🔌 API Documentation

### Base URL
```
http://localhost:5000/api/v1
```

### Authentication
All protected routes require:
```
Authorization: Bearer <access_token>
```

### Auth Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/login` | Login (admin/employee) |
| POST | `/auth/refresh` | Refresh access token |
| POST | `/auth/logout` | Logout + invalidate session |
| POST | `/auth/forgot-password` | Send reset email |
| POST | `/auth/reset-password` | Reset password with token |
| GET | `/auth/me` | Get current user profile |

### Employee Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/employees` | List all employees (paginated) |
| POST | `/employees` | Create employee |
| GET | `/employees/:id` | Get employee detail |
| PUT | `/employees/:id` | Update employee |
| DELETE | `/employees/:id` | Soft-delete employee |
| POST | `/employees/:id/photo` | Upload/update face photo |
| GET | `/employees/:id/attendance` | Employee attendance history |
| GET | `/employees/search` | Search employees |

### Attendance Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/attendance/clock-in` | Clock in (face or manual) |
| POST | `/attendance/clock-out` | Clock out |
| POST | `/attendance/face-verify` | Verify face → returns employee |
| GET | `/attendance/today` | Today's attendance list |
| GET | `/attendance/logs` | Paginated attendance logs |
| GET | `/attendance/export` | Export CSV/PDF |
| GET | `/attendance/:id` | Single log detail |

### Analytics Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/analytics/summary` | Dashboard summary stats |
| GET | `/analytics/daily` | Daily attendance trend |
| GET | `/analytics/department` | Per-department stats |
| GET | `/analytics/late-arrivals` | Late arrival report |
| GET | `/analytics/overtime` | Overtime report |

### Notification Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/notifications` | List notifications |
| PUT | `/notifications/:id/read` | Mark as read |
| PUT | `/notifications/read-all` | Mark all as read |

### WebSocket Events

```
ws://localhost:5000/ws/attendance

Events emitted:
  attendance.clock_in    → { employee_id, name, timestamp, photo_url }
  attendance.clock_out   → { employee_id, name, timestamp }
  attendance.alert       → { type, message, employee_id }
  attendance.unknown     → { frame_snapshot, timestamp }
```

---

## 🔐 Security Features

- **Password Hashing**: bcrypt with cost factor 12
- **JWT**: Access token (15 min) + Refresh token (7 days)
- **Rate Limiting**: 100 req/min per IP, 10 login attempts/min
- **SQL Injection Prevention**: Parameterized queries via psycopg2
- **Input Validation**: Marshmallow schemas on all endpoints
- **Secure File Upload**: MIME-type validation, size limits, UUID filenames
- **CORS**: Configured for Flutter app origins only
- **Liveness Detection**: Blink detection prevents photo spoofing

---

## 🧪 Testing

```bash
# Backend tests
cd backend
pytest tests/ -v --cov=. --cov-report=html

# Flutter tests
cd flutter_app
flutter test
```

---

## 🐳 Deployment

### Production with Docker
```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Manual (Ubuntu/Debian)
```bash
# Backend
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 wsgi:app

# Nginx (see docker/nginx.conf)
sudo systemctl restart nginx
```

---

## 📊 Default Credentials (Dev Only)
```
Admin:    admin@attendease.com / Admin@1234
Employee: emp001@attendease.com / Emp@1234
```
