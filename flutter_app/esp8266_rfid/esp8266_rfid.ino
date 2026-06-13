/*
 * ============================================================
 * AttendEase — ESP8266 + MFRC522 RFID Attendance System
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
 *   RST  → D3 (GPIO0)
 *   3.3V → 3.3V  ← NOT 5V, will damage module
 *
 * Optional feedback:
 *   Green LED  → D1 (GPIO5) → 220Ω resistor → GND
 *   Red LED    → D2 (GPIO4) → 220Ω resistor → GND
 *   Buzzer     → D4 (GPIO2) → GND
 *
 * Libraries (install via Arduino Library Manager):
 *   - MFRC522 by GithubCommunity
 *   - ArduinoJson by Benoit Blanchon (v6.x)
 *   - ESP8266WiFi (comes with ESP8266 board package)
 *
 * Board settings:
 *   Board         : NodeMCU 1.0 (ESP-12E Module)
 *   Upload Speed  : 115200
 *   Flash Size    : 4MB (FS:2MB OTA:~1019KB)
 * ============================================================
 */

#include <SPI.h>
#include <MFRC522.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>

// ============================================================
// CONFIGURATION — EDIT THESE
// ============================================================

const char* WIFI_SSID     = "HUAWEI-2.4G-az9q";
const char* WIFI_PASSWORD = "K9XhMnmN";
const char* SERVER_BASE   = "https://attendance-rfid.onrender.com/api/v1";
const char* API_KEY       = "yvd1bxmlA9jRRYp2hrvw0QvdoC8AXRJ7ENz5qyrLlDs";
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
String scanModeURL;
bool   adminScanMode = false;
unsigned long lastTapMs = 0;
const unsigned long COOLDOWN_MS = 3000;

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

  tapURL      = String(SERVER_BASE) + "/rfid/tap";
  scanModeURL = String(SERVER_BASE) + "/rfid/scan-mode";
  Serial.print("[URL] tap      → "); Serial.println(tapURL);
  Serial.print("[URL] scanMode → "); Serial.println(scanModeURL);

  connectWiFi();

  Serial.println("\n[READY] Waiting for RFID card tap...");
  beep(1, 100);
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

  unsigned long now = millis();
  if (now - lastTapMs < COOLDOWN_MS) {
    Serial.println("[WAIT] Too fast. Cooldown active.");
    rfid.PICC_HaltA();
    return;
  }
  lastTapMs = now;

  String cardUID = getCardUID();
  Serial.print("[CARD] UID: ");
  Serial.println(cardUID);

  if (adminScanMode) {
    sendScanMode(cardUID);
  } else {
    sendTap(cardUID);
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

// ============================================================
// READ CARD UID
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
// SEND TAP — with retry on timeout (Render cold start)
// ============================================================
void sendTap(String cardUID) {
  Serial.print("[HTTPS] POST tap → ");
  Serial.println(tapURL);

  StaticJsonDocument<128> doc;
  doc["card_uid"]  = cardUID;
  doc["reader_id"] = READER_ID;
  String body;
  serializeJson(doc, body);

  int httpCode = -11;

  for (int attempt = 1; attempt <= 3 && httpCode == -11; attempt++) {
    if (attempt > 1) {
      Serial.printf("[RETRY] Attempt %d/3 — server waking up, waiting 15s...\n", attempt);
      ledFlash(RED_LED, 1, 500);  // slow red blink = waiting
      delay(15000);
    }

    WiFiClientSecure client;
    client.setInsecure();

    HTTPClient http;
    http.begin(client, tapURL);
    http.setTimeout(35000);  // 35s — covers Render cold start
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Camera-Key", API_KEY);

    httpCode = http.POST(body);

    if (httpCode == HTTP_CODE_OK) {
      String response = http.getString();
      Serial.print("[HTTPS] 200 → ");
      Serial.println(response);

      StaticJsonDocument<512> resp;
      if (!deserializeJson(resp, response)) {
        bool        success = resp["success"]       | false;
        const char* name    = resp["employee_name"] | "";
        const char* action  = resp["action"]        | "";
        const char* message = resp["message"]       | "";
        bool        isLate  = resp["is_late"]        | false;
        int         lateMin = resp["late_minutes"]   | 0;

        Serial.println("────────────────────────────────");
        if (success) {
          Serial.printf("[✓] %s | %s\n", name, action);
          Serial.printf("[i] %s\n", message);
          if (isLate) Serial.printf("[!] Late by %d mins\n", lateMin);
          beep(2, 100);
          ledFlash(GREEN_LED, 2, 300);
        } else {
          Serial.printf("[✗] %s\n", message);
          beep(1, 500);
          ledFlash(RED_LED, 3, 200);
        }
        Serial.println("────────────────────────────────");
      }

    } else if (httpCode == -11) {
      Serial.println("[TIMEOUT] No response — Render may be cold starting...");

    } else if (httpCode == 401) {
      Serial.println("[ERROR] 401 — Wrong API key");
      errorFeedback();

    } else if (httpCode < 0) {
      Serial.printf("[ERROR] Connection failed: %d\n", httpCode);
      errorFeedback();

    } else {
      Serial.printf("[ERROR] HTTP %d\n", httpCode);
      if (httpCode > 0) Serial.println(http.getString());
      errorFeedback();
    }

    http.end();
  }

  if (httpCode == -11) {
    Serial.println("[ERROR] Server unreachable after 3 attempts.");
    errorFeedback();
  }
}

// ============================================================
// SEND SCAN MODE (card registration)
// ============================================================
void sendScanMode(String cardUID) {
  Serial.print("[SCAN MODE] Card: ");
  Serial.println(cardUID);

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.begin(client, scanModeURL);
  http.setTimeout(35000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Camera-Key", API_KEY);

  StaticJsonDocument<128> doc;
  doc["card_uid"] = cardUID;
  String body;
  serializeJson(doc, body);

  int httpCode = http.POST(body);
  if (httpCode == HTTP_CODE_OK) {
    Serial.println("[SCAN MODE] UID sent to dashboard");
    beep(3, 80);
    ledFlash(GREEN_LED, 3, 100);
  } else {
    Serial.printf("[SCAN MODE] Error: %d\n", httpCode);
    errorFeedback();
  }
  http.end();
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
// 1 short beep + 3 rapid green flashes   = system ready
// 2 short beeps + 2 green flashes        = attendance recorded
// 1 long beep  + 3 red flashes           = unknown card
// 1 slow red blink (repeated)            = waiting for server (cold start)
// 1 very long beep + 5 red flashes       = server error / unreachable
