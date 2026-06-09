# AttendEase — Deployment Guide

## What you need
- A Linux VPS (DigitalOcean, Hetzner, Linode — $6/month works)
- Docker + Docker Compose installed on the server
- A domain name (optional but recommended)

---

## Step 1 — Get a server

Cheapest options (all support Docker):
- **Hetzner CX22** — €4/mo, 2 vCPU, 4 GB RAM (recommended)
- **DigitalOcean Droplet** — $6/mo, 1 vCPU, 1 GB RAM
- **Contabo VPS** — €5/mo, 4 vCPU, 6 GB RAM

After creating the server, SSH into it:
```bash
ssh root@YOUR_SERVER_IP
```

---

## Step 2 — Install Docker on the server

```bash
curl -fsSL https://get.docker.com | sh
apt-get install -y docker-compose-plugin
```

---

## Step 3 — Build the Flutter web app (on your laptop)

Run this once on your Windows machine before deploying:

```powershell
cd flutter_app
flutter build web --release --dart-define=API_BASE_URL=/api/v1
```

This creates `flutter_app/build/web/`. The app will call `/api/v1` which nginx proxies to Flask.

---

## Step 4 — Upload your project to the server

From your Windows machine:
```powershell
# Install rsync or use scp
scp -r C:\Users\hp\Music\attendease_complete\ams root@YOUR_SERVER_IP:/opt/attendease
```

Or use **FileZilla** (SFTP) to upload the folder to `/opt/attendease` on the server.

---

## Step 5 — Create your .env file on the server

SSH into the server, then:
```bash
cd /opt/attendease

# Generate secure keys
python3 -c "import secrets; print(secrets.token_hex(32))"  # run twice

cp .env.example .env
nano .env
```

Fill in your `.env`:
```
POSTGRES_DB=attendease
POSTGRES_USER=attendease
POSTGRES_PASSWORD=your_strong_password_here
SECRET_KEY=paste_first_generated_key_here
JWT_SECRET_KEY=paste_second_generated_key_here
FLASK_ENV=production
CORS_ORIGINS=http://YOUR_SERVER_IP
```

---

## Step 6 — Start everything

```bash
cd /opt/attendease
docker compose up -d
```

That's it. Docker will:
1. Start PostgreSQL and create the database
2. Build and start the Flask backend
3. Start nginx serving the Flutter web app

Check it's running:
```bash
docker compose ps
docker compose logs backend   # check for errors
```

Open your browser: `http://YOUR_SERVER_IP`

---

## Step 7 — Add a domain (optional but professional)

1. Buy a domain (Namecheap, ~$10/year)
2. Point the domain's A record to your server IP
3. Update `.env`: `CORS_ORIGINS=https://yourdomain.com`
4. Install SSL (free):

```bash
apt-get install -y certbot
certbot certonly --standalone -d yourdomain.com
```

Then update `docker/nginx.conf` to add HTTPS (ask for help if needed).

---

## Sending to a new customer

For each new customer you sell to, you have two options:

### Option A — Same server, new account (easiest)
1. Log into your admin panel at `http://YOUR_SERVER_IP`
2. Create a new company/admin account for the customer
3. Send them the URL + their login credentials

### Option B — Their own server (for enterprise customers who want privacy)
1. Give them a copy of this folder
2. They follow Steps 1–6 above on their own server
3. Or you set it up for them (charge a setup fee)

---

## Updating the app

When you make changes:
```bash
# On your laptop — rebuild Flutter web
cd flutter_app
flutter build web --release --dart-define=API_BASE_URL=/api/v1

# Upload new build to server
scp -r build/web root@YOUR_SERVER_IP:/opt/attendease/flutter_app/build/

# On the server — restart backend if Python changed
cd /opt/attendease
docker compose restart backend
```

---

## Useful commands

```bash
# View logs
docker compose logs -f backend

# Restart everything
docker compose restart

# Stop everything
docker compose down

# Backup database
docker compose exec db pg_dump -U attendease attendease > backup.sql

# Restore database
docker compose exec -T db psql -U attendease attendease < backup.sql
```
