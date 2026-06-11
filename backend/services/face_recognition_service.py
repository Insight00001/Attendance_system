"""
services/face_recognition_service.py
Core face recognition using face_recognition (dlib) + OpenCV.
Handles: encoding, identification, liveness detection.
"""

import io
import os
import pickle
import hashlib
import base64
import uuid
from typing import Optional, Tuple

import numpy as np
from PIL import Image
from flask import current_app

from models import Employee, FaceEncoding
from config.database import db
from utils.logger import get_logger

logger = get_logger(__name__)

# face_recognition (dlib) and OpenCV are heavy native libs that are not
# installed on lightweight cloud deployments (e.g. Render free tier).
# Import them lazily so the rest of the API still works without them.
try:
    import face_recognition
    import cv2
    FACE_LIBS_AVAILABLE = True
except ImportError:
    face_recognition = None  # type: ignore
    cv2 = None               # type: ignore
    FACE_LIBS_AVAILABLE = False
    logger.warning(
        "face_recognition/cv2 not installed — face clock-in disabled. "
        "All other API features remain available."
    )

_FACE_UNAVAILABLE_MSG = (
    "Face recognition is not available on this server. "
    "Use RFID or manual clock-in instead."
)


class FaceRecognitionService:
    """
    Production-grade face recognition service.

    Methods:
        encode_face(image_bytes)    → np.ndarray encoding
        identify_face(image_bytes)  → (Employee, confidence) or (None, score)
        save_encoding(employee_id, image_bytes) → FaceEncoding record
        detect_liveness(frames)     → bool (blink detected)
    """

    # EAR threshold for blink detection (Eye Aspect Ratio)
    EAR_THRESHOLD = 0.25
    EAR_CONSEC_FRAMES = 2

    # Facial landmark indices for eyes (dlib 68-point model)
    LEFT_EYE_IDX  = list(range(36, 42))
    RIGHT_EYE_IDX = list(range(42, 48))

    # ── Face Encoding ─────────────────────────────────────────

    @staticmethod
    def load_image_from_bytes(image_bytes: bytes) -> np.ndarray:
        """Convert raw bytes to RGB numpy array for face_recognition."""
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        return np.array(pil_image)

    @classmethod
    def encode_face(cls, image_bytes: bytes) -> Tuple[Optional[np.ndarray], str]:
        """
        Extract face encoding from image bytes.
        Returns (encoding_array, error_message).
        """
        if not FACE_LIBS_AVAILABLE:
            return None, _FACE_UNAVAILABLE_MSG
        try:
            rgb_image = cls.load_image_from_bytes(image_bytes)

            # Detect face locations (HOG model — faster, less accurate than CNN)
            face_locations = face_recognition.face_locations(rgb_image, model="hog")

            if not face_locations:
                return None, "No face detected in the image"
            if len(face_locations) > 1:
                return None, "Multiple faces detected. Please use a single-face photo."

            # Extract 128-dimension encoding
            encodings = face_recognition.face_encodings(rgb_image, face_locations)
            if not encodings:
                return None, "Could not compute face encoding"

            return encodings[0], ""

        except Exception as e:
            logger.error(f"Face encoding error: {e}")
            return None, f"Face encoding failed: {str(e)}"

    @classmethod
    def save_encoding(
        cls,
        employee_id: str,
        image_bytes: bytes,
    ) -> Tuple[Optional[FaceEncoding], str]:
        """
        Encode a face from image and persist to database.
        Replaces existing primary encoding if one exists.
        """
        encoding, error = cls.encode_face(image_bytes)
        if error:
            return None, error

        # Serialize encoding as bytes (pickle of numpy array)
        encoding_bytes = pickle.dumps(encoding)
        photo_hash = hashlib.sha256(image_bytes).hexdigest()

        # Mark old primary encodings as non-primary
        FaceEncoding.query.filter_by(
            employee_id=employee_id, is_primary=True
        ).update({"is_primary": False})

        face_enc = FaceEncoding(
            employee_id=employee_id,
            encoding_data=encoding_bytes,
            photo_hash=photo_hash,
            is_primary=True,
        )
        db.session.add(face_enc)
        db.session.commit()

        logger.info(f"Face encoding saved for employee {employee_id}")
        return face_enc, ""

    # ── Face Identification ───────────────────────────────────

    @classmethod
    def identify_face(
        cls,
        image_bytes: bytes,
    ) -> Tuple[Optional[Employee], float]:
        """
        Identify an employee from a face image.

        Algorithm:
            1. Encode incoming face
            2. Load all primary encodings from DB
            3. Compute face_distance (lower = more similar)
            4. Return best match if within tolerance

        Returns:
            (employee, confidence_percent) or (None, 0.0)
        """
        if not FACE_LIBS_AVAILABLE:
            logger.warning("identify_face called but face libs unavailable")
            return None, 0.0
        query_encoding, error = cls.encode_face(image_bytes)
        if error:
            logger.warning(f"Face identification failed: {error}")
            return None, 0.0

        # Load all active employee encodings
        all_encodings = (
            FaceEncoding.query
            .join(Employee, FaceEncoding.employee_id == Employee.id)
            .filter(
                FaceEncoding.is_primary == True,
                Employee.employment_status == "active",
            )
            .all()
        )

        if not all_encodings:
            logger.warning("No face encodings in database")
            return None, 0.0

        # Build comparison lists
        known_encodings = []
        known_employees = []
        for fe in all_encodings:
            try:
                enc = pickle.loads(fe.encoding_data)
                known_encodings.append(enc)
                known_employees.append(fe.employee)
            except Exception as e:
                logger.error(f"Failed to load encoding {fe.id}: {e}")

        if not known_encodings:
            return None, 0.0

        tolerance = current_app.config.get("FACE_TOLERANCE", 0.5)

        # Compute distances (face_distance returns 0.0 = identical, 1.0 = completely different)
        distances = face_recognition.face_distance(known_encodings, query_encoding)
        best_idx = int(np.argmin(distances))
        best_distance = float(distances[best_idx])

        # Convert distance to confidence (1.0 - distance) × 100
        confidence = round((1.0 - best_distance) * 100, 2)

        if best_distance <= tolerance:
            employee = known_employees[best_idx]
            logger.info(
                f"Face matched: {employee.full_name} | "
                f"distance={best_distance:.3f} | confidence={confidence:.1f}%"
            )
            return employee, confidence

        logger.info(f"No match (best distance={best_distance:.3f}, threshold={tolerance})")
        return None, confidence

    # ── Snapshot Saving ───────────────────────────────────────

    @staticmethod
    def save_snapshot(image_bytes: bytes, folder_key: str = "clock_in") -> Optional[str]:
        """
        Save a face snapshot for audit trail.
        Returns relative file path.
        """
        snapshot_dir = current_app.config.get("FACE_SNAPSHOT_FOLDER", "uploads/snapshots")
        os.makedirs(snapshot_dir, exist_ok=True)

        filename = f"{uuid.uuid4()}.jpg"
        filepath = os.path.join(snapshot_dir, filename)

        # Save as JPEG for storage efficiency
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        pil_image.save(filepath, "JPEG", quality=80)

        return f"snapshots/{filename}"

    # ── Liveness Detection (Blink) ────────────────────────────

    @classmethod
    def compute_ear(cls, eye_landmarks: list) -> float:
        """
        Eye Aspect Ratio (EAR) for blink detection.
        EAR = (||p2-p6|| + ||p3-p5||) / (2 × ||p1-p4||)
        Low EAR → eye closed (blink).
        """
        p = np.array(eye_landmarks)
        A = np.linalg.norm(p[1] - p[5])
        B = np.linalg.norm(p[2] - p[4])
        C = np.linalg.norm(p[0] - p[3])
        return (A + B) / (2.0 * C) if C > 0 else 0.0

    @classmethod
    def detect_liveness_from_frames(cls, frame_b64_list: list) -> bool:
        """
        Detect liveness from a sequence of base64 frames.
        Returns True if at least one blink is detected.

        frame_b64_list: list of base64-encoded JPEG frames (minimum 10 recommended)
        """
        if not FACE_LIBS_AVAILABLE:
            logger.warning("Liveness check skipped — face libs unavailable")
            return False
        required_blinks = current_app.config.get("LIVENESS_BLINK_THRESHOLD", 3)
        blink_count = 0
        consec_frames_below_threshold = 0

        for b64_frame in frame_b64_list:
            try:
                image_bytes = base64.b64decode(b64_frame)
                rgb = cls.load_image_from_bytes(image_bytes)
                gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)

                # Use face_recognition to get landmarks
                landmarks_list = face_recognition.face_landmarks(rgb)
                if not landmarks_list:
                    continue

                landmarks = landmarks_list[0]
                left_eye  = [list(pt) for pt in landmarks.get("left_eye", [])]
                right_eye = [list(pt) for pt in landmarks.get("right_eye", [])]

                if not left_eye or not right_eye:
                    continue

                left_ear  = cls.compute_ear(left_eye)
                right_ear = cls.compute_ear(right_eye)
                ear = (left_ear + right_ear) / 2.0

                if ear < cls.EAR_THRESHOLD:
                    consec_frames_below_threshold += 1
                else:
                    if consec_frames_below_threshold >= cls.EAR_CONSEC_FRAMES:
                        blink_count += 1
                    consec_frames_below_threshold = 0

            except Exception as e:
                logger.debug(f"Liveness frame error: {e}")
                continue

        logger.info(f"Liveness check: {blink_count} blinks (required: {required_blinks})")
        return blink_count >= required_blinks

    # ── Base64 Utilities ──────────────────────────────────────

    @staticmethod
    def base64_to_bytes(b64_str: str) -> bytes:
        """Strip data URI prefix and decode base64."""
        if "," in b64_str:
            b64_str = b64_str.split(",", 1)[1]
        return base64.b64decode(b64_str)
