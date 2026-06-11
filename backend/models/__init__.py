"""
models/ — SQLAlchemy ORM Models
All models in one file for simplicity; can be split per model in large projects.
"""

import uuid
from datetime import datetime, timezone
from config.database import db
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB, BYTEA, INET


def utcnow():
    return datetime.now(timezone.utc)


# ─────────────────────────────────────────────────────────────
# DEPARTMENT
# ─────────────────────────────────────────────────────────────

class Department(db.Model):
    __tablename__ = "departments"

    id          = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name        = db.Column(db.String(100), nullable=False, unique=True)
    code        = db.Column(db.String(20), nullable=False, unique=True)
    description = db.Column(db.Text)
    manager_id  = db.Column(UUID(as_uuid=True), db.ForeignKey("employees.id"), nullable=True)
    is_active   = db.Column(db.Boolean, nullable=False, default=True)
    created_at  = db.Column(db.DateTime(timezone=True), default=utcnow)
    updated_at  = db.Column(db.DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    employees   = db.relationship("Employee", back_populates="department",
                                   foreign_keys="Employee.department_id")

    def to_dict(self):
        return {
            "id": str(self.id), "name": self.name, "code": self.code,
            "description": self.description, "is_active": self.is_active,
        }


# ─────────────────────────────────────────────────────────────
# ROLE
# ─────────────────────────────────────────────────────────────

class Role(db.Model):
    __tablename__ = "roles"

    id          = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name        = db.Column(db.String(100), nullable=False, unique=True)
    code        = db.Column(db.String(50), nullable=False, unique=True)
    description = db.Column(db.Text)
    is_active   = db.Column(db.Boolean, nullable=False, default=True)
    created_at  = db.Column(db.DateTime(timezone=True), default=utcnow)

    def to_dict(self):
        return {"id": str(self.id), "name": self.name, "code": self.code}


# ─────────────────────────────────────────────────────────────
# USER
# ─────────────────────────────────────────────────────────────

class User(db.Model):
    __tablename__ = "users"

    id                  = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email               = db.Column(db.String(255), nullable=False, unique=True, index=True)
    password_hash       = db.Column(db.String(255), nullable=False)
    user_role           = db.Column(
        db.Enum("super_admin", "admin", "hr", "employee", name="user_role"),
        nullable=False, default="employee"
    )
    is_active           = db.Column(db.Boolean, nullable=False, default=True)
    is_verified         = db.Column(db.Boolean, nullable=False, default=False)
    last_login_at       = db.Column(db.DateTime(timezone=True))
    failed_attempts     = db.Column(db.Integer, nullable=False, default=0)
    locked_until        = db.Column(db.DateTime(timezone=True))
    reset_token         = db.Column(db.String(255))
    reset_token_expires = db.Column(db.DateTime(timezone=True))
    created_at          = db.Column(db.DateTime(timezone=True), default=utcnow)
    updated_at          = db.Column(db.DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    # Relationships
    employee    = db.relationship("Employee", back_populates="user",
                                   foreign_keys="Employee.user_id", uselist=False)
    sessions    = db.relationship("Session", back_populates="user", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            "id": str(self.id), "email": self.email, "role": self.user_role,
            "is_active": self.is_active, "is_verified": self.is_verified,
            "last_login_at": self.last_login_at.isoformat() if self.last_login_at else None,
        }

    def is_locked(self) -> bool:
        if self.locked_until and self.locked_until > utcnow():
            return True
        return False

    def is_admin(self) -> bool:
        return self.user_role in ("super_admin", "admin", "hr")


# ─────────────────────────────────────────────────────────────
# EMPLOYEE
# ─────────────────────────────────────────────────────────────

class Employee(db.Model):
    __tablename__ = "employees"

    id                = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id           = db.Column(UUID(as_uuid=True), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    employee_id       = db.Column(db.String(20), nullable=False, unique=True)
    first_name        = db.Column(db.String(100), nullable=False)
    last_name         = db.Column(db.String(100), nullable=False)
    middle_name       = db.Column(db.String(100))
    gender            = db.Column(db.String(30), default="prefer_not_to_say")
    date_of_birth     = db.Column(db.Date)
    phone             = db.Column(db.String(20))
    address           = db.Column(db.Text)
    department_id     = db.Column(UUID(as_uuid=True), db.ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    role_id           = db.Column(UUID(as_uuid=True), db.ForeignKey("roles.id", ondelete="SET NULL"), nullable=True)
    job_title         = db.Column(db.String(150))
    employment_status = db.Column(db.String(20), nullable=False, default="active")
    hire_date         = db.Column(db.Date, nullable=False, default=datetime.utcnow)
    termination_date  = db.Column(db.Date)
    photo_url         = db.Column(db.String(500))
    card_uid          = db.Column(db.String(50), unique=True, nullable=True)
    shift_start       = db.Column(db.Time, default=sa.text("'08:00:00'"))
    shift_end         = db.Column(db.Time, default=sa.text("'17:00:00'"))
    late_threshold    = db.Column(db.Integer, nullable=False, default=15)
    created_by        = db.Column(UUID(as_uuid=True), db.ForeignKey("users.id"))
    created_at        = db.Column(db.DateTime(timezone=True), default=utcnow)
    updated_at        = db.Column(db.DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    # Relationships
    user          = db.relationship("User", back_populates="employee",
                                     foreign_keys=[user_id])
    department    = db.relationship("Department", back_populates="employees", foreign_keys=[department_id])
    role          = db.relationship("Role", foreign_keys=[role_id])
    attendance_logs = db.relationship("AttendanceLog", back_populates="employee", cascade="all, delete-orphan")
    face_encodings  = db.relationship("FaceEncoding", back_populates="employee", cascade="all, delete-orphan")

    @property
    def full_name(self) -> str:
        return f"{self.first_name} {self.last_name}"

    def to_dict(self, include_sensitive: bool = False) -> dict:
        data = {
            "id": str(self.id),
            "employee_id": self.employee_id,
            "full_name": self.full_name,
            "first_name": self.first_name,
            "last_name": self.last_name,
            "gender": self.gender,
            "phone": self.phone,
            "job_title": self.job_title,
            "employment_status": self.employment_status,
            "hire_date": self.hire_date.isoformat() if self.hire_date else None,
            "photo_url": self.photo_url,
            
            "shift_start": self.shift_start.strftime("%H:%M") if self.shift_start else None,
            "shift_end": self.shift_end.strftime("%H:%M") if self.shift_end else None,
            "late_threshold": self.late_threshold,
            "department": self.department.to_dict() if self.department else None,
            "role": self.role.to_dict() if self.role else None,
            "email": self.user.email if self.user else None,
            "card_uid": self.card_uid,
        }
        if include_sensitive:
            data["date_of_birth"] = self.date_of_birth.isoformat() if self.date_of_birth else None
            data["address"] = self.address
        return data


# ─────────────────────────────────────────────────────────────
# FACE ENCODING
# ─────────────────────────────────────────────────────────────

class FaceEncoding(db.Model):
    __tablename__ = "face_encodings"

    id               = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    employee_id      = db.Column(UUID(as_uuid=True), db.ForeignKey("employees.id", ondelete="CASCADE"), nullable=False)
    encoding_data    = db.Column(BYTEA, nullable=False)       # serialized numpy array
    encoding_version = db.Column(db.String(20), default="1.0")
    photo_hash       = db.Column(db.String(64))               # SHA-256 of source photo
    confidence_score = db.Column(db.Float)
    is_primary       = db.Column(db.Boolean, nullable=False, default=True)
    created_at       = db.Column(db.DateTime(timezone=True), default=utcnow)

    employee = db.relationship("Employee", back_populates="face_encodings")


# ─────────────────────────────────────────────────────────────
# ATTENDANCE LOG
# ─────────────────────────────────────────────────────────────

class AttendanceLog(db.Model):
    __tablename__ = "attendance_logs"

    id                = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    employee_id       = db.Column(UUID(as_uuid=True), db.ForeignKey("employees.id", ondelete="CASCADE"), nullable=False)
    attendance_date   = db.Column(db.Date, nullable=False, default=datetime.utcnow)
    clock_in          = db.Column(db.DateTime(timezone=True))
    clock_out         = db.Column(db.DateTime(timezone=True))
    clock_in_method   = db.Column(db.String(20), default="face_recognition")
    clock_out_method  = db.Column(db.String(20), default="face_recognition")
    status            = db.Column(db.String(20), nullable=False, default="present")
    is_late           = db.Column(db.Boolean, nullable=False, default=False)
    late_minutes      = db.Column(db.Integer, default=0)
    overtime_minutes  = db.Column(db.Integer, default=0)
    working_minutes   = db.Column(db.Integer, default=0)
    confidence_in     = db.Column(db.Float)
    confidence_out    = db.Column(db.Float)
    clock_in_photo    = db.Column(db.String(500))
    clock_out_photo   = db.Column(db.String(500))
    notes             = db.Column(db.Text)
    flagged           = db.Column(db.Boolean, nullable=False, default=False)
    created_at        = db.Column(db.DateTime(timezone=True), default=utcnow)
    updated_at        = db.Column(db.DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    employee = db.relationship("Employee", back_populates="attendance_logs")

    __table_args__ = (
        db.UniqueConstraint("employee_id", "attendance_date", name="uq_employee_date"),
    )

    def to_dict(self) -> dict:
        return {
            "id": str(self.id),
            "employee_id": str(self.employee_id),
            "employee_name": self.employee.full_name if self.employee else None,
            "attendance_date": self.attendance_date.isoformat() if self.attendance_date else None,
            "clock_in": self.clock_in.isoformat() if self.clock_in else None,
            "clock_out": self.clock_out.isoformat() if self.clock_out else None,
            "clock_in_method": self.clock_in_method,
            "clock_out_method": self.clock_out_method,
            "status": self.status,
            "is_late": self.is_late,
            "late_minutes": self.late_minutes,
            "overtime_minutes": self.overtime_minutes,
            "working_minutes": self.working_minutes,
            "confidence_in": self.confidence_in,
            "flagged": self.flagged,
        }


# ─────────────────────────────────────────────────────────────
# SESSION (Refresh token store)
# ─────────────────────────────────────────────────────────────

class Session(db.Model):
    __tablename__ = "sessions"

    id            = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id       = db.Column(UUID(as_uuid=True), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    refresh_token = db.Column(db.String(500), nullable=False, unique=True)
    device_info   = db.Column(JSONB)
    expires_at    = db.Column(db.DateTime(timezone=True), nullable=False)
    is_revoked    = db.Column(db.Boolean, nullable=False, default=False)
    created_at    = db.Column(db.DateTime(timezone=True), default=utcnow)

    user = db.relationship("User", back_populates="sessions")


# ─────────────────────────────────────────────────────────────
# NOTIFICATION
# ─────────────────────────────────────────────────────────────

class Notification(db.Model):
    __tablename__ = "notifications"

    id          = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id     = db.Column(UUID(as_uuid=True), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=True)
    employee_id = db.Column(UUID(as_uuid=True), db.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True)
    type        = db.Column(db.String(20), nullable=False, default="info")
    title       = db.Column(db.String(255), nullable=False)
    message     = db.Column(db.Text, nullable=False)
    extra_data  = db.Column(JSONB, name="metadata")   # 'metadata' reserved by SQLAlchemy
    is_read     = db.Column(db.Boolean, nullable=False, default=False)
    read_at     = db.Column(db.DateTime(timezone=True))
    created_at  = db.Column(db.DateTime(timezone=True), default=utcnow)

    def to_dict(self) -> dict:
        return {
            "id": str(self.id),
            "type": self.type,
            "title": self.title,
            "message": self.message,
            "metadata": self.extra_data,
            "is_read": self.is_read,
            "read_at": self.read_at.isoformat() if self.read_at else None,
            "created_at": self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────
# AUDIT LOG
# ─────────────────────────────────────────────────────────────

class AuditLog(db.Model):
    __tablename__ = "audit_logs"

    id          = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id     = db.Column(UUID(as_uuid=True), db.ForeignKey("users.id", ondelete="SET NULL"))
    action      = db.Column(db.String(100), nullable=False)
    entity_type = db.Column(db.String(50))
    entity_id   = db.Column(UUID(as_uuid=True))
    old_value   = db.Column(JSONB)
    new_value   = db.Column(JSONB)
    ip_address  = db.Column(INET)
    user_agent  = db.Column(db.Text)
    created_at  = db.Column(db.DateTime(timezone=True), default=utcnow)