# AttendEase — Per-Customer Deployment (Option A)

Each customer gets their **own isolated stack**: one backend container +
one PostgreSQL database + unique secrets. No customer ever shares data
or API keys with another.

## Requirements (on the customer's server / PC)

- Docker + Docker Compose (Docker Desktop on Windows)
- Python 3 (only to run the env generator)

## Install a new customer

```bash
cd deploy
python generate_env.py        # answers: customer name, admin email/password
docker compose up -d --build
```

Verify: open `http://<server-ip>:5000/health` → `{"status": "ok"}`.

The first start automatically creates all database tables and the admin
account (from `ADMIN_EMAIL` / `ADMIN_PASSWORD` in `.env`).

## Connect the RFID readers

Power on each reader → connect to the **AttendEase-Setup** hotspot
(password `attendease`) → on the setup page enter:

- the customer's WiFi
- **Server IP**: the server's LAN IP (find with `ipconfig` / `ip a`)
- **Port**: value of `BACKEND_PORT` (default 5000)
- **API key**: the `CAMERA_API_KEY` printed by `generate_env.py`
  (also in `deploy/.env`)

## Connect the dashboard app

Point the Flutter app's server address at `http://<server-ip>:5000`.
Log in with the admin credentials from `generate_env.py`.

## Day-2 operations

| Task | Command (from `deploy/`) |
|---|---|
| View logs | `docker compose logs -f backend` |
| Restart | `docker compose restart` |
| Update to new version | `git pull && docker compose up -d --build` |
| Backup database | `docker compose exec db pg_dump -U attendease attendease > backup_$(date +%F).sql` |
| Restore database | `docker compose exec -T db psql -U attendease attendease < backup_2026-06-12.sql` |
| Stop everything | `docker compose down` (data persists in volumes) |
| Wipe completely | `docker compose down -v` ⚠ deletes all data |

## Notes

- `.env` contains all of this customer's secrets — keep it safe,
  never commit it, never reuse it for another customer.
- The Docker image uses the lightweight requirements (no dlib/opencv):
  RFID attendance, dashboard, analytics, and leave management all work.
  Face-recognition clock-in runs on a separate kiosk machine if used.
- The database is only reachable from inside the Docker network;
  only port 5000 (the API) is exposed.
