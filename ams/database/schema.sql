-- ============================================================
-- AttendEase — PostgreSQL Schema v1.0
-- Run: psql -U postgres -d attendease -f schema.sql
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_role AS ENUM ('super_admin', 'admin', 'hr', 'employee');
CREATE TYPE employment_status AS ENUM ('active', 'inactive', 'suspended', 'terminated');
CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'late', 'half_day', 'on_leave');
CREATE TYPE clock_method AS ENUM ('face_recognition', 'manual', 'pin', 'card');
CREATE TYPE notification_type AS ENUM ('success', 'warning', 'alert', 'info');
CREATE TYPE gender_type AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');

-- ============================================================
-- DEPARTMENTS
-- ============================================================

CREATE TABLE departments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    code        VARCHAR(20) NOT NULL UNIQUE,
    description TEXT,
    manager_id  UUID,                              -- FK added after employees table
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ROLES
-- ============================================================

CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    code        VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USERS (Authentication table)
-- ============================================================

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    user_role       user_role NOT NULL DEFAULT 'employee',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    last_login_at   TIMESTAMPTZ,
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until    TIMESTAMPTZ,
    reset_token     VARCHAR(255),
    reset_token_expires TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- EMPLOYEES
-- ============================================================

CREATE TABLE employees (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id     VARCHAR(20) NOT NULL UNIQUE,    -- e.g., EMP-2024-001
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    middle_name     VARCHAR(100),
    gender          gender_type NOT NULL DEFAULT 'prefer_not_to_say',
    date_of_birth   DATE,
    phone           VARCHAR(20),
    address         TEXT,
    department_id   UUID REFERENCES departments(id) ON DELETE SET NULL,
    role_id         UUID REFERENCES roles(id) ON DELETE SET NULL,
    job_title       VARCHAR(150),
    employment_status employment_status NOT NULL DEFAULT 'active',
    hire_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    termination_date DATE,
    photo_url       VARCHAR(500),                   -- path to stored photo
    shift_start     TIME NOT NULL DEFAULT '08:00:00',
    shift_end       TIME NOT NULL DEFAULT '17:00:00',
    late_threshold  INTEGER NOT NULL DEFAULT 15,    -- minutes grace after shift_start
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add FK from departments to employees for manager
ALTER TABLE departments
    ADD CONSTRAINT fk_dept_manager
    FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL;

-- ============================================================
-- FACE ENCODINGS
-- ============================================================

CREATE TABLE face_encodings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    encoding_data   BYTEA NOT NULL,                 -- serialized numpy array
    encoding_version VARCHAR(20) NOT NULL DEFAULT '1.0',
    photo_hash      VARCHAR(64),                    -- SHA-256 of source photo
    confidence_score FLOAT,
    is_primary      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_face_encodings_employee ON face_encodings(employee_id);

-- ============================================================
-- ATTENDANCE LOGS
-- ============================================================

CREATE TABLE attendance_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    clock_in        TIMESTAMPTZ,
    clock_out       TIMESTAMPTZ,
    clock_in_method  clock_method DEFAULT 'face_recognition',
    clock_out_method clock_method DEFAULT 'face_recognition',
    status          attendance_status NOT NULL DEFAULT 'present',
    is_late         BOOLEAN NOT NULL DEFAULT FALSE,
    late_minutes    INTEGER DEFAULT 0,
    overtime_minutes INTEGER DEFAULT 0,
    working_minutes  INTEGER DEFAULT 0,             -- computed on clock-out
    confidence_in   FLOAT,                          -- face recognition confidence
    confidence_out  FLOAT,
    clock_in_photo  VARCHAR(500),                   -- snapshot path
    clock_out_photo VARCHAR(500),
    notes           TEXT,
    flagged         BOOLEAN NOT NULL DEFAULT FALSE, -- suspicious activity flag
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Prevent duplicate clock-in per employee per day
    CONSTRAINT uq_employee_date UNIQUE (employee_id, attendance_date)
);

CREATE INDEX idx_attendance_date ON attendance_logs(attendance_date);
CREATE INDEX idx_attendance_employee ON attendance_logs(employee_id);
CREATE INDEX idx_attendance_status ON attendance_logs(status);
CREATE INDEX idx_attendance_flagged ON attendance_logs(flagged) WHERE flagged = TRUE;

-- ============================================================
-- SESSIONS (Refresh token management)
-- ============================================================

CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token   VARCHAR(500) NOT NULL UNIQUE,
    device_info     JSONB,                          -- { os, browser, ip, device_name }
    expires_at      TIMESTAMPTZ NOT NULL,
    is_revoked      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_token ON sessions(refresh_token);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL = broadcast
    employee_id     UUID REFERENCES employees(id) ON DELETE SET NULL,
    type            notification_type NOT NULL DEFAULT 'info',
    title           VARCHAR(255) NOT NULL,
    message         TEXT NOT NULL,
    metadata        JSONB,                          -- extra data (photo, confidence etc.)
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);

-- ============================================================
-- AUDIT LOG
-- ============================================================

CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      VARCHAR(100) NOT NULL,              -- e.g., 'employee.create'
    entity_type VARCHAR(50),                        -- e.g., 'employee'
    entity_id   UUID,
    old_value   JSONB,
    new_value   JSONB,
    ip_address  INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ============================================================
-- LEAVE REQUESTS (Bonus feature)
-- ============================================================

CREATE TABLE leave_requests (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    reason          TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_by     UUID REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_attendance_updated_at BEFORE UPDATE ON attendance_logs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_face_encoding_updated_at BEFORE UPDATE ON face_encodings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Auto-compute working_minutes on clock-out
CREATE OR REPLACE FUNCTION compute_working_minutes()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.clock_out IS NOT NULL AND NEW.clock_in IS NOT NULL THEN
        NEW.working_minutes = EXTRACT(EPOCH FROM (NEW.clock_out - NEW.clock_in)) / 60;
        -- Overtime: minutes beyond 8 hours (480 minutes)
        NEW.overtime_minutes = GREATEST(0, NEW.working_minutes - 480);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_compute_working_minutes
    BEFORE INSERT OR UPDATE OF clock_out ON attendance_logs
    FOR EACH ROW EXECUTE FUNCTION compute_working_minutes();

-- Employee ID generator function
CREATE OR REPLACE FUNCTION generate_employee_id()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    seq_num INTEGER;
    new_id VARCHAR(20);
BEGIN
    year_part := TO_CHAR(NOW(), 'YYYY');
    SELECT COUNT(*) + 1 INTO seq_num FROM employees
    WHERE EXTRACT(YEAR FROM hire_date) = EXTRACT(YEAR FROM NOW());
    new_id := 'EMP-' || year_part || '-' || LPAD(seq_num::TEXT, 4, '0');
    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SEED DATA — Departments and Roles
-- ============================================================

INSERT INTO departments (name, code, description) VALUES
    ('Engineering',     'ENG',  'Software and hardware engineering'),
    ('Human Resources', 'HR',   'Talent acquisition and management'),
    ('Finance',         'FIN',  'Accounting and financial planning'),
    ('Operations',      'OPS',  'Day-to-day business operations'),
    ('Sales',           'SAL',  'Revenue and client relations'),
    ('Marketing',       'MKT',  'Brand and digital marketing');

INSERT INTO roles (name, code, description) VALUES
    ('Software Engineer',    'SWE',  'Develops software products'),
    ('Senior Engineer',      'SNR',  'Leads technical initiatives'),
    ('HR Manager',           'HRM',  'Manages HR functions'),
    ('HR Officer',           'HRO',  'HR day-to-day tasks'),
    ('Finance Analyst',      'FAN',  'Financial reporting'),
    ('Operations Manager',   'OPM',  'Operations oversight'),
    ('Sales Executive',      'SEX',  'Client sales'),
    ('Marketing Specialist', 'MKS',  'Marketing campaigns');

-- ============================================================
-- VIEWS — Convenience Queries
-- ============================================================

-- Active employees with department and role names
CREATE VIEW vw_employees AS
SELECT
    e.id,
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.first_name,
    e.last_name,
    e.gender,
    e.phone,
    e.job_title,
    e.employment_status,
    e.hire_date,
    e.photo_url,
    e.shift_start,
    e.shift_end,
    e.late_threshold,
    d.name AS department_name,
    d.code AS department_code,
    r.name AS role_name,
    u.email,
    u.user_role,
    u.is_active,
    u.last_login_at
FROM employees e
LEFT JOIN departments d ON e.department_id = d.id
LEFT JOIN roles r ON e.role_id = r.id
JOIN users u ON e.user_id = u.id;

-- Today's attendance summary
CREATE VIEW vw_today_attendance AS
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    d.name AS department,
    al.clock_in,
    al.clock_out,
    al.status,
    al.is_late,
    al.late_minutes,
    al.working_minutes,
    al.clock_in_method
FROM employees e
LEFT JOIN attendance_logs al ON e.id = al.employee_id AND al.attendance_date = CURRENT_DATE
LEFT JOIN departments d ON e.department_id = d.id
WHERE e.employment_status = 'active';


CREATE TABLE rfid_cards (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_uid    VARCHAR(50) NOT NULL UNIQUE,
    label       VARCHAR(100),              -- optional name/label
    is_assigned BOOLEAN NOT NULL DEFAULT FALSE,
    assigned_to UUID REFERENCES employees(id) ON DELETE SET NULL,
    first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tap_count   INTEGER NOT NULL DEFAULT 1
);
SELECT attendance_date, COUNT(*) as count, 
       SUM(CASE WHEN status IN ('present','late') THEN 1 ELSE 0 END) as present
FROM attendance_logs
GROUP BY attendance_date
ORDER BY attendance_date DESC
LIMIT 10;

CREATE INDEX idx_rfid_cards_uid        ON rfid_cards(card_uid);
CREATE INDEX idx_rfid_cards_unassigned ON rfid_cards(is_assigned) WHERE is_assigned = FALSE;


GRANT ALL PRIVILEGES ON TABLE rfid_cards TO attendease_user;
GRANT ALL PRIVILEGES ON TABLE leave_requests TO attendease_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO attendease_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO attendease_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO attendease_user;


-- Drop old constraint
ALTER TABLE employees 
DROP CONSTRAINT IF EXISTS employees_created_by_fkey;

-- Re-add with SET NULL on delete
ALTER TABLE employees 
ADD CONSTRAINT employees_created_by_fkey 
FOREIGN KEY (created_by) 
REFERENCES users(id) 
ON DELETE SET NULL;