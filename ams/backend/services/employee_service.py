"""
services/employee_service.py — Employee CRUD and management
"""

import os
import uuid
import secrets
import hashlib
from typing import Optional, Tuple
from werkzeug.datastructures import FileStorage

from config.database import db
from models import Employee, User, Department, Role, FaceEncoding
from services.auth_service import AuthService
from services.face_recognition_service import FaceRecognitionService
from utils.logger import get_logger

logger = get_logger(__name__)


class EmployeeService:
    """Employee lifecycle management."""

    ALLOWED_PHOTO_MIMES = {"image/jpeg", "image/png", "image/webp"}

    # ── Generate Employee ID ──────────────────────────────────

    @staticmethod
    def generate_employee_id() -> str:
        """Generate unique Employee ID: EMP-YYYY-NNNN."""
        from datetime import datetime
        year = datetime.now().year
        count = Employee.query.filter(
            db.extract("year", Employee.hire_date) == year
        ).count()
        return f"EMP-{year}-{str(count + 1).zfill(4)}"

    # ── Create Employee ───────────────────────────────────────

    @classmethod
    def create_employee(
        cls,
        data: dict,
        photo: Optional[FileStorage] = None,
        created_by_id: Optional[str] = None,
    ) -> Tuple[Optional[Employee], Optional[str]]:
        """
        Create a new employee with user account.
        data keys: email, password, first_name, last_name, department_id,
                   role_id, job_title, phone, gender, shift_start, shift_end, ...
        """
        email = data.get("email", "").lower().strip()

        # Validate email uniqueness
        if User.query.filter_by(email=email).first():
            return None, f"Email {email} is already registered"

        # Create user account
        password = data.get("password") or secrets.token_urlsafe(12)
        user = User(
            email=email,
            password_hash=AuthService.hash_password(password),
            user_role=data.get("user_role", "employee"),
            is_active=True,
            is_verified=True,
        )
        db.session.add(user)
        db.session.flush()  # Get user.id

        # Handle photo upload
        photo_url = None
        if photo and photo.filename:
            photo_url, err = cls.save_employee_photo(photo)
            if err:
                db.session.rollback()
                return None, err

        # Create employee record
        from datetime import datetime
        employee = Employee(
            user_id=user.id,
            employee_id=cls.generate_employee_id(),
            first_name=data["first_name"].strip(),
            last_name=data["last_name"].strip(),
            middle_name=data.get("middle_name", "").strip() or None,
            gender=data.get("gender", "prefer_not_to_say"),
            date_of_birth=data.get("date_of_birth"),
            phone=data.get("phone"),
            address=data.get("address"),
            department_id=data.get("department_id"),
            role_id=data.get("role_id"),
            job_title=data.get("job_title"),
            hire_date=data.get("hire_date") or datetime.utcnow().date(),
            photo_url=photo_url,
            shift_start=data.get("shift_start", "08:00"),
            shift_end=data.get("shift_end", "17:00"),
            late_threshold=int(data.get("late_threshold", 15)),
            employment_status="active",
            created_by=created_by_id,
        )
        db.session.add(employee)
        db.session.commit()

        # If photo was uploaded, also save face encoding
        if photo_url:
            photo.seek(0)
            image_bytes = photo.read()
            _, enc_err = FaceRecognitionService.save_encoding(str(employee.id), image_bytes)
            if enc_err:
                logger.warning(f"Face encoding failed for {employee.full_name}: {enc_err}")

        logger.info(f"Employee created: {employee.employee_id} — {employee.full_name}")
        return employee, None

    # ── Update Employee ───────────────────────────────────────

    @classmethod
    def update_employee(
        cls,
        employee_id: str,
        data: dict,
        photo: Optional[FileStorage] = None,
    ) -> Tuple[Optional[Employee], Optional[str]]:
        """Update employee fields."""
        employee = Employee.query.filter_by(id=employee_id).first()
        if not employee:
            return None, "Employee not found"

        # Updatable fields
        updatable = [
            "first_name", "last_name", "middle_name", "gender", "date_of_birth",
            "phone", "address", "department_id", "role_id", "job_title",
            "shift_start", "shift_end", "late_threshold", "employment_status",
        ]
        for field in updatable:
            if field in data:
                setattr(employee, field, data[field])

        # Update email if provided
        if "email" in data:
            new_email = data["email"].lower().strip()
            if new_email != employee.user.email:
                if User.query.filter_by(email=new_email).first():
                    return None, "Email already in use"
                employee.user.email = new_email

        # Update photo
        if photo and photo.filename:
            photo_url, err = cls.save_employee_photo(photo)
            if err:
                return None, err
            employee.photo_url = photo_url

            # Re-encode face
            photo.seek(0)
            image_bytes = photo.read()
            _, enc_err = FaceRecognitionService.save_encoding(str(employee.id), image_bytes)
            if enc_err:
                logger.warning(f"Face re-encoding failed: {enc_err}")

        db.session.commit()
        logger.info(f"Employee updated: {employee.employee_id}")
        return employee, None

    # ── Soft Delete ───────────────────────────────────────────

    @staticmethod
    def deactivate_employee(employee_id: str, hard_delete: bool = False) -> Tuple[bool, Optional[str]]:
        """
        Delete employee.
        hard_delete=True  → permanently removes user + employee rows (email freed)
        hard_delete=False → soft delete (terminated status, keeps audit trail)
        """
        employee = Employee.query.filter_by(id=employee_id).first()
        if not employee:
            return False, "Employee not found"

        if hard_delete:
            # Hard delete — removes everything, frees the email
            user = User.query.filter_by(id=employee.user_id).first()
            db.session.delete(employee)
            if user:
                db.session.delete(user)
        else:
            # Soft delete — append a suffix to free the email for reuse
            from datetime import datetime
            suffix = datetime.utcnow().strftime("%Y%m%d%H%M%S")
            employee.employment_status = "terminated"
            employee.user.is_active = False
            employee.user.email = f"{employee.user.email}.deleted_{suffix}"
            from datetime import datetime
            employee.termination_date = datetime.utcnow().date()

        db.session.commit()
        logger.info(f"Employee {'hard' if hard_delete else 'soft'} deleted: {employee_id}")
        return True, None

    # ── Search ────────────────────────────────────────────────

    @staticmethod
    def search_employees(
        query: Optional[str] = None,
        department_id: Optional[str] = None,
        status: Optional[str] = "active",
        page: int = 1,
        per_page: int = 20,
    ) -> dict:
        """Search + filter employees with pagination."""
        q = Employee.query

        if status:
            q = q.filter(Employee.employment_status == status)
        if department_id:
            q = q.filter(Employee.department_id == department_id)
        if query:
            search = f"%{query}%"
            q = q.filter(
                db.or_(
                    Employee.first_name.ilike(search),
                    Employee.last_name.ilike(search),
                    Employee.employee_id.ilike(search),
                    Employee.job_title.ilike(search),
                )
            )

        pagination = q.order_by(Employee.last_name.asc()).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return {
            "employees": [e.to_dict() for e in pagination.items],
            "total": pagination.total,
            "pages": pagination.pages,
            "page": page,
            "per_page": per_page,
        }

    # ── Photo Upload ──────────────────────────────────────────

    @classmethod
    def save_employee_photo(cls, photo: FileStorage) -> Tuple[Optional[str], Optional[str]]:
        """Validate and save employee photo. Returns (relative_path, error)."""
        from flask import current_app
        import magic

        MAX_SIZE = 5 * 1024 * 1024  # 5 MB
        photo.seek(0, 2)
        size = photo.tell()
        photo.seek(0)

        if size > MAX_SIZE:
            return None, "Photo must be under 5 MB"

        # MIME validation using python-magic (not just extension)
        header = photo.read(2048)
        photo.seek(0)
        mime = magic.from_buffer(header, mime=True)
        if mime not in cls.ALLOWED_PHOTO_MIMES:
            return None, f"Invalid file type: {mime}. Allowed: JPEG, PNG, WebP"

        ext = mime.split("/")[1].replace("jpeg", "jpg")
        filename = f"{uuid.uuid4()}.{ext}"
        upload_dir = os.path.join(current_app.config["UPLOAD_FOLDER"], "photos")
        os.makedirs(upload_dir, exist_ok=True)
        filepath = os.path.join(upload_dir, filename)
        photo.save(filepath)

        return f"photos/{filename}", None
    



