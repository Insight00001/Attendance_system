# AttendEase Reader — Customer Setup Guide

No technical knowledge needed. Takes about 2 minutes.

## First-time setup

1. **Plug in the reader** (USB power adapter or power bank).
2. On your phone or laptop, open **WiFi settings** and connect to:
   - Network: **AttendEase-Setup**
   - Password: **attendease**
3. A setup page opens automatically. (If it doesn't, open a browser
   and go to **192.168.4.1**.)
4. Tap **Configure WiFi**, then fill in:
   - **Your WiFi network** — pick it from the list and enter its password
   - **Server IP or hostname** — provided by your installer
   - **Server port** — usually 5000
   - **API key** — provided by your installer
   - **Reader name** — e.g. `main-entrance`
5. Tap **Save**. The reader restarts and connects.
6. **3 green flashes + 1 beep** = ready to use.

## Light & sound guide

| Signal | Meaning |
|---|---|
| Red light stays on | Setup mode — hotspot is active |
| 3 green flashes + 1 beep | Connected and ready |
| 2 green flashes + 2 beeps | Attendance recorded |
| 2 slow red flashes + 1 beep | Clock-out too soon after clock-in |
| 3 red flashes + 1 long beep | Card not assigned — contact admin |
| 5 red flashes + 1 very long beep | Can't reach server — check network |

## Changed your WiFi name or password?

Nothing to press. The reader will fail to connect, wait 30 seconds,
and automatically reopen the **AttendEase-Setup** hotspot. Repeat the
first-time setup steps.

## Registering employee cards

Tap any new card on the reader once. It appears under
**Unassigned cards** in the AttendEase admin dashboard, where the
admin assigns it to an employee.
