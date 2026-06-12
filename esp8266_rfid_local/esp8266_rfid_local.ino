/*
 * ============================================================
 * AttendEase — ESP8266 + MFRC522 RFID Attendance (LOCAL server)
 * ============================================================
 * Board   : NodeMCU ESP8266 or Wemos D1 Mini
 * Module  : MFRC522 RFID Reader
 *
 * Wiring (MFRC522 → NodeMCU):
 *   SDA  → D8 (GPIO15)
 *   SCK  → D5 (GPIO14)
 *   MOSI → D7 (GPIO13)
 *   MISO → D6 (GPIO12)
 *   GND  → GND
 *   RST  → D3 (GPIO0)   ← boot strap pin: must be HIGH at power-on.
 *                          RC522 RST idles high, so this is fine, but
 *                          disconnect if upload/boot issues occur.
 *   3.3V → 3.3V         ← NOT 5V, will damage module
 *
 * Optional feedback:
 *   Green LED  → D1 (GPIO5) → 220Ω resistor → GND
 *   Red LED    → D2 (GPIO4) → 220Ω resistor → GND
 *   Buzzer     → D4 (GPIO2) → GND
 *     GPIO2 is a boot strap pin (also onboard LED, active LOW).
 *     An active buzzer here may chirp briefly at boot — harmless.
 *     Use an ACTIVE buzzer; a low-resistance passive buzzer can
 *     pull the pin low and prevent booting.
 *
 * Libraries (Arduino Library Manager):
 *   - MFRC522 by GithubCommunity
 *   - ArduinoJson by Benoit Blanchon (v6.x)
 *   - ESP8266 board package (ESP8266WiFi / ESP8266HTTPClient)
 *
 * Board settings:
 *   Board        : NodeMCU 1.0 (ESP-12E Module)
 *   Upload Speed : 115200
 *   Flash Size   : 4MB (FS:2MB OTA:~1019KB)
 *
 * Card registration flow (no scan mode needed):
 *   Tap an unknown card → backend auto-registers it in rfid_cards
 *   and it appears under "Unassigned cards" in the admin dashboard,
 *   where it can be assigned to an employee.
 * ============================================================
 */

#include <SPI.h>
#include <MFRC522.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#include <ArduinoJson.h>
#include "secrets.h"   // WiFi + API credentials (gitignored — see secrets.h.example)

// ============================================================
// CONFIGURATION — EDIT THESE
// ============================================================
const char* WIFI_SSID     = SECRET_WIFI_SSID;
const char* WIFI_PASSWORD = SECRET_WIFI_PASSWORD;
const char* SERVER_IP     = "192.168.100.10";  // your PC IP
const char* SERVER_PORT   = "5000";
const char* API_KEY       = SECRET_API_KEY;    // matches backend CAMERA_API_KEY
const char* READER_ID     = "zics-entrance-1";

// ============================================================
// PINS
// ============================================================
#define SS_PIN    15   // D8
#define RST_PIN   0    // D3
#define GREEN_LED 5    // D1 — success
#define RED_LED   4    // D2 — error / unknown card
#define BUZZER    2    // D4 — beep feedback

// ============================================================
// GLOBALS
// ============================================================
MFRC522 rfid(SS_PIN, RST_PIN);

String tapURL;

// Per-card debounce: same card ignored for DEBOUNCE_MS,
// a DIFFERENT card is accepted immediately (back-to-back taps work).
String        lastUID    = "";
unsigned long lastTapMs  = 0;
const unsigned long DEBOUNCE_MS = 5000;

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n========================================");
  Serial.println("  AttendEase RFID System Starting...");
  Serial.println("========================================");

  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED,   OUTPUT);
  pinMode(BUZZER,    OUTPUT);
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED,   LOW);
  digitalWrite(BUZZER,    LOW);

  SPI.begin();
  rfid.PCD_Init();
  rfid.PCD_DumpVersionToSerial();
  Serial.println("[OK] RFID reader ready");

  tapURL  = "http://";
  tapURL += SERVER_IP;
  tapURL += ":";
  tapURL += SERVER_PORT;
  tapURL += "/api/v1/rfid/tap";

  connectWiFi();

  Serial.println("\n[READY] Waiting for RFID card tap...");
  beep(1, 100);             // 1 short beep = ready
  ledFlash(GREEN_LED, 3, 150);
}

// ============================================================
// MAIN LOOP
// ============================================================
void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Lost. Reconnecting...");
    connectWiFi();
  }

  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial())   return;

  String cardUID = getCardUID();

  // Halt the card right away — no need to hold the session
  // open while the HTTP request runs.
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  // Per-card debounce
  unsigned long now = millis();
  if (cardUID == lastUID && now - lastTapMs < DEBOUNCE_MS) {
    Serial.println("[WAIT] Same card too fast. Ignored.");
    return;
  }
  lastUID   = cardUID;
  lastTapMs = now;

  Serial.print("[CARD] UID: ");
  Serial.println(cardUID);

  sendTap(cardUID);
}

// ============================================================
// READ CARD UID  (uppercase, colon-separated — matches backend)
// ============================================================
String getCardUID() {
  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
    if (i < rfid.uid.size - 1) uid += ":";
  }
  uid.toUpperCase();
  return uid;
}

// ============================================================
// SEND TAP TO BACKEND
// ============================================================
// Returns HTTP code (-1 = connection failure)
int postTap(const String& cardUID, String& response) {
  WiFiClient client;
  HTTPClient http;
  http.begin(client, tapURL);
  http.setTimeout(15000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Camera-Key", API_KEY);

  StaticJsonDocument<128> doc;
  doc["card_uid"]  = cardUID;
  doc["reader_id"] = READER_ID;
  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  if (code == HTTP_CODE_OK) response = http.getString();
  http.end();
  return code;
}

void sendTap(String cardUID) {
  Serial.print("[HTTP] POST tap → ");
  Serial.println(tapURL);

  String response;
  int httpCode = postTap(cardUID, response);

  // One retry on connection failure (server busy / WiFi blip)
  if (httpCode == -1) {
    Serial.println("[HTTP] Connection failed. Retrying once...");
    delay(500);
    httpCode = postTap(cardUID, response);
  }

  if (httpCode == HTTP_CODE_OK) {
    Serial.print("[HTTP] 200 → ");
    Serial.println(response);

    StaticJsonDocument<512> resp;
    if (deserializeJson(resp, response)) {
      Serial.println("[ERROR] Bad JSON in response");
      errorFeedback();
      return;
    }

    bool        success = resp["success"]       | false;
    const char* name    = resp["employee_name"] | "";
    const char* action  = resp["action"]        | "";
    const char* message = resp["message"]       | "";
    bool        isLate  = resp["is_late"]       | false;
    int         lateMin = resp["late_minutes"]  | 0;

    Serial.println("────────────────────────────────");
    if (success) {
      Serial.printf("[✓] %s | %s\n", name, action);
      Serial.printf("[i] %s\n", message);
      if (isLate) Serial.printf("[!] Late by %d mins\n", lateMin);
      beep(2, 100);                  // 2 short beeps
      ledFlash(GREEN_LED, 2, 300);   // 2 green flashes

    } else if (strcmp(action, "too_soon") == 0) {
      // Clock-out attempted too soon after clock-in
      Serial.printf("[~] %s\n", message);
      beep(1, 300);                  // 1 medium beep
      ledFlash(RED_LED, 2, 300);     // 2 slow red flashes

    } else {
      // Unknown / unassigned card
      Serial.printf("[✗] %s\n", message);
      beep(1, 500);                  // 1 long beep
      ledFlash(RED_LED, 3, 200);     // 3 red flashes
    }
    Serial.println("────────────────────────────────");

  } else if (httpCode == 401) {
    Serial.println("[ERROR] 401 — Wrong API key");
    errorFeedback();

  } else if (httpCode == -1) {
    Serial.println("[ERROR] Cannot reach server. Check IP and Flask.");
    errorFeedback();

  } else {
    Serial.printf("[ERROR] HTTP %d\n", httpCode);
    errorFeedback();
  }
}

// ============================================================
// WIFI
// ============================================================
void connectWiFi() {
  Serial.printf("[WIFI] Connecting to %s ", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > 15000) {
      Serial.println("\n[WIFI] Timeout. Retrying in 10s...");
      delay(10000);
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
      start = millis();
      continue;
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("[WIFI] Connected! IP: ");
  Serial.println(WiFi.localIP());
}

// ============================================================
// FEEDBACK HELPERS
// ============================================================
void beep(int times, int durationMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(BUZZER, HIGH);
    delay(durationMs);
    digitalWrite(BUZZER, LOW);
    delay(durationMs);
  }
}

void ledFlash(int pin, int times, int durationMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(pin, HIGH);
    delay(durationMs);
    digitalWrite(pin, LOW);
    delay(durationMs);
  }
}

void errorFeedback() {
  beep(1, 800);
  ledFlash(RED_LED, 5, 100);
}

// ============================================================
// FEEDBACK PATTERNS
// ============================================================
// 1 short beep  + 3 rapid green flashes = system ready
// 2 short beeps + 2 green flashes       = attendance recorded
// 1 medium beep + 2 slow red flashes    = clock-out too soon
// 1 long beep   + 3 red flashes         = unknown card
// 1 very long beep + 5 red flashes      = server error
