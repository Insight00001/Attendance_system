# AttendEase — Free-Tier Deployment Guide

Stack: **Supabase** (PostgreSQL) + **Render** (Flask API) + **Vercel** (Flutter web).

---

## Step 1 — Database on Supabase

1. Sign up at [supabase.com](https://supabase.com) → **New project**. Choose a strong DB password and a region close to your users.
2. Go to **Project Settings → Database → Connection string** and copy the **Session pooler** URI (not "Direct connection" — Render's free tier needs the IPv4-compatible pooler). It looks like:
   ```
   postgresql://postgres.xxxx:[PASSWORD]@aws-0-eu-west-1.pooler.supabase.com:5432/postgres
   ```
3. Create your schema: open **SQL Editor** in Supabase and run your table-creation SQL (employees, attendance_logs, leave_requests, departments, users, face_encodings, notifications, settings). The `leave_type` column is auto-added by the app on first boot.
4. To migrate existing local data:
   ```
   pg_dump -U attendease_user -d attendease --no-owner --no-acl > backup.sql
   psql "<SUPABASE_SESSION_POOLER_URI>" < backup.sql
   ```

> ⚠ Supabase free tier **pauses projects after ~7 days of inactivity**.
> The UptimeRobot keepalive in Step 4 prevents this by generating regular DB traffic.

---

## Step 2 — Backend on Render

1. Push the project to GitHub (the root `.gitignore` already excludes `venv/`, `.env`, builds).
2. Sign up at [render.com](https://render.com) with GitHub → **New → Blueprint** → select the repo. Render reads `render.yaml` automatically.
   (Or manually: **New → Web Service**, root directory `backend`,
   build `pip install -r requirements-render.txt`,
   start `gunicorn -k eventlet -w 1 wsgi:app`.)
3. Fill in the environment variables it asks for:
   | Variable | Value |
   |---|---|
   | `DATABASE_URL` | Supabase **Session pooler** URI from Step 1 |
   | `CORS_ORIGINS` | `https://YOUR-APP.vercel.app` (add after Step 3; no trailing slash) |
   | `MAIL_USERNAME` / `MAIL_PASSWORD` | your SMTP credentials (optional) |
4. Deploy. First build takes a few minutes. Verify: `https://YOUR-API.onrender.com/health` → `{"status":"ok","database":"ok"}`.

Notes:
- `requirements-render.txt` deliberately **excludes face-recognition/dlib/opencv** — they don't fit in the free tier's 512 MB. The API boots fine without them; **face clock-in returns a friendly "use RFID or manual" message**. Keep running face clock-in on your local kiosk machine pointed at the same Supabase database if you need it.
- Free instances **sleep after 15 min idle**; first request after that takes ~1 min.

---

## Step 3 — Flutter web on Vercel

Option A — quickest (build locally, deploy the output):
1. ```
   cd flutter_app
   flutter build web --release --dart-define=API_BASE_URL=https://YOUR-API.onrender.com/api/v1 --dart-define=WS_URL=https://YOUR-API.onrender.com
   ```
2. Install the Vercel CLI (`npm i -g vercel`), then:
   ```
   cd build/web
   vercel --prod
   ```

Option B — auto-deploy from GitHub:
1. In Vercel: **Add New → Project** → import the repo, set **Root Directory** to `flutter_app`. The included `vercel.json` clones the Flutter SDK and builds for you.
2. Add Vercel env vars `API_BASE_URL` and `WS_URL` (same values as above).

---

## Step 4 — Wire it together

1. Set `CORS_ORIGINS=https://YOUR-APP.vercel.app` on Render and redeploy.
2. Create a free [UptimeRobot](https://uptimerobot.com) monitor: HTTP(S), URL `https://YOUR-API.onrender.com/health`, interval 5 min. This keeps Render awake **and** Supabase unpaused.
3. Test in the browser: login → dashboard → analytics → PDF/Excel export.

---

## What runs where

| Feature | Web (Vercel + Render) | Local / kiosk machine |
|---|---|---|
| Admin dashboard, analytics, exports | ✅ | ✅ |
| Employees, leave, RFID management | ✅ | ✅ |
| Manual + RFID clock-in | ✅ | ✅ |
| Face recognition clock-in | ❌ (libs too heavy for free tier) | ✅ |
