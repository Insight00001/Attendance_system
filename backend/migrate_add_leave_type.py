"""
migrate_add_leave_type.py
─────────────────────────
One-time migration: adds `leave_type` column to `leave_requests`.

Run once from the backend directory:
    python migrate_add_leave_type.py

Safe to run multiple times — skips if the column already exists.
"""

import sys
from app import create_app
from config.database import db
from sqlalchemy import text


VALID_TYPES = "annual, sick, emergency, unpaid, absence, other"


def run():
    app = create_app()
    with app.app_context():
        # ── 1. Check if column already exists ──────────────────
        exists = db.session.execute(text("""
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_name   = 'leave_requests'
              AND column_name  = 'leave_type'
        """)).scalar()

        if exists:
            print("✓ Column 'leave_type' already exists — nothing to do.")
            return

        # ── 2. Add the column with a sensible default ───────────
        print("Adding column 'leave_type' to 'leave_requests' ...")
        db.session.execute(text("""
            ALTER TABLE leave_requests
            ADD COLUMN leave_type VARCHAR(20) NOT NULL DEFAULT 'annual'
        """))
        db.session.commit()
        print(f"  ✓ Column added (default = 'annual')")

        # ── 3. Optional: add a CHECK constraint ─────────────────
        try:
            db.session.execute(text(f"""
                ALTER TABLE leave_requests
                ADD CONSTRAINT chk_leave_type
                CHECK (leave_type IN ({', '.join(f"'{t.strip()}'" for t in VALID_TYPES.split(','))}))
            """))
            db.session.commit()
            print(f"  ✓ CHECK constraint added: ({VALID_TYPES})")
        except Exception as e:
            db.session.rollback()
            print(f"  ⚠ Could not add CHECK constraint (non-fatal): {e}")

        print("\nMigration complete. Restart the Flask server.")


if __name__ == "__main__":
    run()
