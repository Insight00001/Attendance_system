/*
 * ============================================================
 * AttendEase — ESP8266 RFID Reader (Customer Edition)
 * Captive-portal setup: NO hardcoded credentials.
 * ============================================================
 *
 * FIRST BOOT (or after WiFi change):
 *   1. Device broadcasts WiFi hotspot "AttendEase-Setup"
 *      (password: attendease)
 *   2. Customer connects with any phone/laptop
 *   3. Setup page opens automatically (or browse to 192.168.4.1)
 *   4. They pick their WiFi, enter password, server address,
 *      API key, and a reader name → Save
 *   5. Device reboots, connects, and starts reading cards.
 *
 * Settings are stored in flash (LittleFS + WiFi NVRAM) and
 * survive power loss. If the device can't reach the saved WiFi
 * (e.g. customer changed their router password), the setup
 * hotspot reappears automatically.
 *
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
 *   3.3V → 3.3V  ← NOT 5V
 *
 * Feedback:
 *   Green LED → D1 (GPIO5) → 220Ω → GND
 *   Red LED   → D2 (GPIO4) → 220Ω → GND
 *   Buzzer    → D4 (GPIO2) → GND   (active buzzer)
 *
 * LED meanings:
 *   Red solid            = setup mode (hotspot active)
 *   3 green flashes      = connected & ready
 *   2 green + 2 beeps    = attendance recorded
 *   3 red + 1 long beep  = unknown card
 *   5 red + v.long beep  = server error
 *
 * Libraries (Arduino Library Manager):
 *   - WiFiManager by tzapu (v2.x)
 *   - MFRC522 by GithubCommunity
 *   - ArduinoJson by Benoit Blanchon (v6.x)
 *
 * Board settings:
 *   Board      : NodeMCU 1.0 (ESP-12E Module)
 *   Flash Size : 4MB (FS:2MB OTA:~1019KB)  ← FS needed for config
 * ============================================================
 */

#include <FS.h>
#include <LittleFS.h>
#include <SPI.h>
#include <MFRC522.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClient.h>
#include <WiFiManager.h>
#include <ArduinoJson.h>

// ============================================================
// SETUP HOTSPOT (what the customer connects to)
// ============================================================
const char* AP_NAME     = "AttendEase-Setup";
const char* AP_PASSWORD = "attendease";   // min 8 chars

// ============================================================
// PINS
// ============================================================
#define SS_PIN    15   // D8
#define RST_PIN   0    // D3
#define GREEN_LED 5    // D1
#define RED_LED   4    // D2
#define BUZZER    2    // D4

// ============================================================
// RUNTIME CONFIG (filled from portal / flash — no defaults
// containing real credentials)
// ============================================================
char cfgServerHost[41] = "";            // e.g. 192.168.100.10
char cfgServerPort[6]  = "5000";
char cfgApiKey[80]     = "";
char cfgReaderId[33]   = "entrance-1";

const char* CONFIG_FILE = "/config.json";
bool shouldSaveConfig = false;

// ============================================================
// GLOBALS
// ============================================================
MFRC522 rfid(SS_PIN, RST_PIN);
String  tapURL;

String        lastUID   = "";
unsigned long lastTapMs = 0;
const unsigned long DEBOUNCE_MS = 5000;

unsigned long wifiLostSince = 0;
const unsigned long WIFI_GRACE_MS = 30000; // 30s offline → reopen portal

// ============================================================
// CONFIG STORAGE (LittleFS)
// ============================================================
bool loadConfig() {
  if (!LittleFS.begin()) {
    Serial.println("[FS] Mount failed");
    return false;
  }
  if (!LittleFS.exists(CONFIG_FILE)) return false;

  File f = LittleFS.open(CONFIG_FILE, "r");
  if (!f) return false;

  StaticJsonDocument<384> doc;
  DeserializationError err = deserializeJson(doc, f);
  f.close();
  if (err) {
    Serial.println("[FS] Bad config JSON");
    return false;
  }

  strlcpy(cfgServerHost, doc["server_host"] | "",           sizeof(cfgServerHost));
  strlcpy(cfgServerPort, doc["server_port"] | "5000",       sizeof(cfgServerPort));
  strlcpy(cfgApiKey,     doc["api_key"]     | "",           sizeof(cfgApiKey));
  strlcpy(cfgReaderId,   doc["reader_id"]   | "entrance-1", sizeof(cfgReaderId));

  Serial.println("[FS] Config loaded");
  return strlen(cfgServerHost) > 0 && strlen(cfgApiKey) > 0;
}

void saveConfig() {
  StaticJsonDocument<384> doc;
  doc["server_host"] = cfgServerHost;
  doc["server_port"] = cfgServerPort;
  doc["api_key"]     = cfgApiKey;
  doc["reader_id"]   = cfgReaderId;

  File f = LittleFS.open(CONFIG_FILE, "w");
  if (!f) {
    Serial.println("[FS] Cannot write config");
    return;
  }
  serializeJson(doc, f);
  f.close();
  Serial.println("[FS] Config saved");
}

void saveConfigCallback() { shouldSaveConfig = true; }

// ============================================================
// SETUP PORTAL
// ============================================================
// Blocks until configured (or restarts on timeout).
void runSetupPortal(bool forcePortal) {
  WiFiManager wm;

  WiFiManagerParameter pHost("host",   "Server IP or hostname", cfgServerHost, 40);
  WiFiManagerParameter pPort("port",   "Server port",           cfgServerPort, 5);
  WiFiManagerParameter pKey ("apikey", "API key",               cfgApiKey,     79);
  WiFiManagerParameter pRdr ("reader", "Reader name (e.g. main-entrance)", cfgReaderId, 32);

  wm.addParameter(&pHost);
  wm.addParameter(&pPort);
  wm.addParameter(&pKey);
  wm.addParameter(&pRdr);

  wm.setSaveConfigCallback(saveConfigCallback);
  wm.setConfigPortalTimeout(300);          // 5 min, then retry/restart
  wm.setTitle("AttendEase Setup");

  digitalWrite(RED_LED, HIGH);             // red solid = setup mode

  bool ok;
  if (forcePortal) {
    ok = wm.startConfigPortal(AP_NAME, AP_PASSWORD);
  } else {
    // Connects with saved WiFi; opens portal only if that fails
    ok = wm.autoConnect(AP_NAME, AP_PASSWORD);
  }

  digitalWrite(RED_LED, LOW);

  if (!ok) {
    Serial.println("[PORTAL] Timeout / failed. Restarting...");
    delay(2000);
    ESP.restart();
  }

  if (shouldSaveConfig) {
    strlcpy(cfgServerHost, pHost.getValue(), sizeof(cfgServerHost));
    strlcpy(cfgServerPort, pPort.getValue(), sizeof(cfgServerPort));
    strlcpy(cfgApiKey,     pKey.getValue(),  sizeof(cfgApiKey));
    strlcpy(cfgReaderId,   pRdr.getValue(),  sizeof(cfgReaderId));
    saveConfig();
    shouldSaveConfig = false;
  }
}

void buildTapURL() {
  tapURL  = "http://";
  tapURL += cfgServerHost;
  tapURL += ":";
  tapURL += cfgServerPort;
  tapURL += "/api/v1/rfid/tap";
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n========================================");
  Serial.println("  AttendEase RFID (Customer Edition)");
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

  bool haveConfig = loadConfig();

  // No server/API config yet → force the portal even if WiFi
  // credentials happen to exist.
  runSetupPortal(!haveConfig);

  // Portal may have just supplied the config
  if (strlen(cfgServerHost) == 0 || strlen(cfgApiKey) == 0) {
    Serial.println("[CFG] Still unconfigured. Reopening portal...");
    runSetupPortal(true);
  }

  buildTapURL();

  Serial.print("[WIFI] Connected! IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("[CFG] Server: ");
  Serial.println(tapURL);
  Serial.printf("[CFG] Reader: %s\n", cfgReaderId);

  Serial.println("\n[READY] Waiting for RFID card tap...");
  beep(1, 100);
  ledFlash(GREEN_LED, 3, 150);
}

// ============================================================
// MAIN LOOP
// ============================================================
void loop() {
  // WiFi watchdog: brief drops → auto-reconnect; offline > 30s
  // (e.g. router password changed) → reopen setup hotspot.
  if (WiFi.status() != WL_CONNECTED) {
    if (wifiLostSince == 0) {
      wifiLostSince = millis();
      Serial.println("[WIFI] Lost. Auto-reconnecting...");
      WiFi.reconnect();
    } else if (millis() - wifiLostSince > WIFI_GRACE_MS) {
      Serial.println("[WIFI] Still offline. Opening setup hotspot...");
      wifiLostSince = 0;
      runSetupPortal(false);   // tries saved WiFi first, then portal
      buildTapURL();
    }
    delay(250);
    return;
  }
  wifiLostSince = 0;

  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial())   return;

  String cardUID = getCardUID();
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  // Per-card debounce (different card accepted immediately)
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
// READ CARD UID (uppercase, colon-separated — matches backend)
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
int postTap(const String& cardUID, String& response) {
  WiFiClient client;
  HTTPClient http;
  http.begin(client, tapURL);
  http.setTimeout(15000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Camera-Key", cfgApiKey);

  StaticJsonDocument<160> doc;
  doc["card_uid"]  = cardUID;
  doc["reader_id"] = cfgReaderId;
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

  if (httpCode == -1) {                 // one retry on connection failure
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
      beep(2, 100);
      ledFlash(GREEN_LED, 2, 300);

    } else if (strcmp(action, "too_soon") == 0) {
      Serial.printf("[~] %s\n", message);
      beep(1, 300);
      ledFlash(RED_LED, 2, 300);

    } else {
      Serial.printf("[✗] %s\n", message);
      beep(1, 500);
      ledFlash(RED_LED, 3, 200);
    }
    Serial.println("────────────────────────────────");

  } else if (httpCode == 401) {
    Serial.println("[ERROR] 401 — Wrong API key. Re-run setup.");
    errorFeedback();

  } else if (httpCode == -1) {
    Serial.println("[ERROR] Cannot reach server. Check address/server.");
    errorFeedback();

  } else {
    Serial.printf("[ERROR] HTTP %d\n", httpCode);
    errorFeedback();
  }
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
