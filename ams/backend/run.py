from app import create_app
from config.database import db
from services.auth_service import AuthService
app = create_app()
with app.app_context():
    db.create_all()
    AuthService.create_admin('admin@attendease.com', 'Admin@1234', 'System Admin')
    print('Admin created successfully')