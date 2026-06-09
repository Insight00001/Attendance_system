"""
tests/test_auth.py — Authentication endpoint tests
Run: pytest tests/test_auth.py -v
"""

import pytest
import json
from app import create_app
from config.config import TestingConfig
from config.database import db as _db


# ── Fixtures ───────────────────────────────────────────────────

@pytest.fixture(scope="session")
def app():
    """Create test Flask app."""
    app = create_app(TestingConfig)
    with app.app_context():
        _db.create_all()
        yield app
        _db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture(scope="session")
def admin_user(app):
    """Create a test admin user once for the session."""
    from services.auth_service import AuthService
    with app.app_context():
        user = AuthService.create_admin(
            email="test_admin@attendease.com",
            password="Admin@1234",
            name="Test Admin",
            role="admin",
        )
        return {"email": "test_admin@attendease.com", "password": "Admin@1234"}


# ── Auth Tests ─────────────────────────────────────────────────

class TestLogin:

    def test_login_success(self, client, admin_user):
        """Valid credentials returns tokens."""
        resp = client.post("/api/v1/auth/login", json=admin_user)
        assert resp.status_code == 200
        data = resp.get_json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["user"]["role"] == "admin"

    def test_login_wrong_password(self, client, admin_user):
        resp = client.post("/api/v1/auth/login", json={
            "email": admin_user["email"],
            "password": "WrongPass!",
        })
        assert resp.status_code == 401

    def test_login_unknown_email(self, client):
        resp = client.post("/api/v1/auth/login", json={
            "email": "nobody@example.com",
            "password": "SomePass@1",
        })
        assert resp.status_code == 401

    def test_login_invalid_email_format(self, client):
        resp = client.post("/api/v1/auth/login", json={
            "email": "not-an-email",
            "password": "Pass@123",
        })
        assert resp.status_code == 422

    def test_login_missing_fields(self, client):
        resp = client.post("/api/v1/auth/login", json={"email": "a@b.com"})
        assert resp.status_code == 422


class TestTokenRefresh:

    def test_refresh_success(self, client, admin_user):
        # Login first
        login_resp = client.post("/api/v1/auth/login", json=admin_user)
        refresh_token = login_resp.get_json()["refresh_token"]

        # Refresh
        resp = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
        assert resp.status_code == 200
        data = resp.get_json()
        assert "access_token" in data

    def test_refresh_invalid_token(self, client):
        resp = client.post("/api/v1/auth/refresh", json={"refresh_token": "garbage.token.here"})
        assert resp.status_code == 401


class TestProtectedRoutes:

    def _get_token(self, client, admin_user):
        resp = client.post("/api/v1/auth/login", json=admin_user)
        return resp.get_json()["access_token"]

    def test_me_authenticated(self, client, admin_user):
        token = self._get_token(client, admin_user)
        resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 200
        assert resp.get_json()["email"] == admin_user["email"]

    def test_me_no_token(self, client):
        resp = client.get("/api/v1/auth/me")
        assert resp.status_code == 401

    def test_me_invalid_token(self, client):
        resp = client.get("/api/v1/auth/me", headers={"Authorization": "Bearer invalid"})
        assert resp.status_code == 401

    def test_logout(self, client, admin_user):
        login_resp = client.post("/api/v1/auth/login", json=admin_user)
        data = login_resp.get_json()
        token = data["access_token"]
        refresh = data["refresh_token"]

        resp = client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": refresh},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200

        # Old refresh token should now be invalid
        ref_resp = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
        assert ref_resp.status_code == 401


# ── Employee Tests ─────────────────────────────────────────────

class TestEmployeeRoutes:

    @pytest.fixture
    def auth_headers(self, client, admin_user):
        resp = client.post("/api/v1/auth/login", json=admin_user)
        token = resp.get_json()["access_token"]
        return {"Authorization": f"Bearer {token}"}

    def test_list_employees(self, client, auth_headers):
        resp = client.get("/api/v1/employees", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert "employees" in data
        assert "total" in data

    def test_create_employee_success(self, client, auth_headers):
        resp = client.post("/api/v1/employees", json={
            "email": "john.doe@company.com",
            "first_name": "John",
            "last_name": "Doe",
            "job_title": "Software Engineer",
        }, headers=auth_headers)
        assert resp.status_code == 201
        data = resp.get_json()
        assert data["employee"]["first_name"] == "John"
        assert data["employee"]["employee_id"].startswith("EMP-")

    def test_create_employee_duplicate_email(self, client, auth_headers):
        payload = {
            "email": "duplicate@company.com",
            "first_name": "Alice",
            "last_name": "Smith",
        }
        client.post("/api/v1/employees", json=payload, headers=auth_headers)
        resp = client.post("/api/v1/employees", json=payload, headers=auth_headers)
        assert resp.status_code == 400

    def test_list_employees_no_auth(self, client):
        resp = client.get("/api/v1/employees")
        assert resp.status_code == 401
