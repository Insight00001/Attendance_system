#!/usr/bin/env bash
# =============================================================
# AttendEase — Local Development Setup Script
# Run: bash setup.sh
# =============================================================
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${BOLD}${BLUE}┌────────────────────────────────────────┐"
echo -e "│   AttendEase — Setup Script            │"
echo -e "└────────────────────────────────────────┘${NC}\n"

# ── 1. Check prerequisites ────────────────────────────────────
echo -e "${BOLD}1. Checking prerequisites...${NC}"

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "  ${YELLOW}✗ $1 not found — please install it${NC}"
    exit 1
  fi
  echo -e "  ${GREEN}✓ $1 found${NC}"
}

check_cmd docker
check_cmd docker-compose
check_cmd python3
check_cmd flutter

# ── 2. Copy .env ──────────────────────────────────────────────
echo -e "\n${BOLD}2. Setting up environment variables...${NC}"
if [ ! -f backend/.env ]; then
  cp backend/.env.example backend/.env
  echo -e "  ${GREEN}✓ Created backend/.env from .env.example${NC}"
  echo -e "  ${YELLOW}⚠  Edit backend/.env with your actual values before production use${NC}"
else
  echo -e "  ${GREEN}✓ backend/.env already exists${NC}"
fi

# ── 3. Generate secure keys ───────────────────────────────────
echo -e "\n${BOLD}3. Generating secure secret keys...${NC}"
JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
REFRESH_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
APP_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

sed -i.bak "s|change-this-to-a-random-32-char-string|${APP_SECRET}|g" backend/.env
sed -i.bak "s|your-super-secret-jwt-key-min-32-chars|${JWT_SECRET}|g" backend/.env
sed -i.bak "s|your-refresh-secret-key-min-32-chars|${REFRESH_SECRET}|g" backend/.env
rm -f backend/.env.bak
echo -e "  ${GREEN}✓ Secret keys generated and written to .env${NC}"

# ── 4. Start Docker services ──────────────────────────────────
echo -e "\n${BOLD}4. Starting Docker services (db + redis + backend + nginx)...${NC}"
docker-compose up -d --build
echo -e "  ${GREEN}✓ Services started${NC}"

# ── 5. Wait for DB to be ready ────────────────────────────────
echo -e "\n${BOLD}5. Waiting for PostgreSQL to be ready...${NC}"
until docker-compose exec -T db pg_isready -U attendease_user -d attendease &>/dev/null; do
  printf '.'
  sleep 2
done
echo -e "\n  ${GREEN}✓ Database is ready${NC}"

# ── 6. Create admin user ──────────────────────────────────────
echo -e "\n${BOLD}6. Creating default admin user...${NC}"
docker-compose exec -T backend python3 -c "
import sys
sys.path.insert(0, '/app')
from app import create_app
from config.config import DevelopmentConfig
from config.database import db
from services.auth_service import AuthService

app = create_app(DevelopmentConfig)
with app.app_context():
    db.create_all()
    try:
        AuthService.create_admin(
            email='admin@attendease.com',
            password='Admin@1234',
            name='System Admin',
            role='super_admin',
        )
        print('Admin user created: admin@attendease.com / Admin@1234')
    except ValueError as e:
        print(f'Admin already exists: {e}')
" 2>/dev/null || echo -e "  ${YELLOW}⚠  Could not create admin (may already exist)${NC}"

echo -e "  ${GREEN}✓ Admin setup complete${NC}"

# ── 7. Flutter setup ──────────────────────────────────────────
echo -e "\n${BOLD}7. Installing Flutter dependencies...${NC}"
cd flutter_app
flutter pub get
echo -e "  ${GREEN}✓ Flutter packages installed${NC}"
cd ..

# ── 8. Summary ────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════════"
echo -e "  AttendEase is ready!"
echo -e "═══════════════════════════════════════════════${NC}"
echo -e ""
echo -e "  ${BOLD}Backend API:${NC}   http://localhost:5000/api/v1"
echo -e "  ${BOLD}Health check:${NC}  http://localhost:5000/health"
echo -e "  ${BOLD}Nginx proxy:${NC}   http://localhost:80"
echo -e ""
echo -e "  ${BOLD}Admin login:${NC}"
echo -e "    Email:    admin@attendease.com"
echo -e "    Password: Admin@1234"
echo -e ""
echo -e "  ${BOLD}Run Flutter app:${NC}"
echo -e "    cd flutter_app"
echo -e "    flutter run              # mobile emulator"
echo -e "    flutter run -d linux     # desktop (Linux)"
echo -e "    flutter run -d macos     # desktop (macOS)"
echo -e "    flutter run -d windows   # desktop (Windows)"
echo -e ""
echo -e "  ${BOLD}View logs:${NC}"
echo -e "    docker-compose logs -f backend"
echo -e ""
echo -e "  ${BOLD}Stop services:${NC}"
echo -e "    docker-compose down"
echo -e ""
