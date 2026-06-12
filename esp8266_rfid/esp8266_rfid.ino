/*
 * AttendEase — ESP8266 + RC522 RFID Reader
 * ─────────────────────────────────────────
 * Reads a card, POSTs the UID to the backend, blinks LED for feedback.
 *
 * Wiring (NodeMCU / Wemos D1 mini -> RC522):
 *   D8 (GPIO15) -> SDA/SS
 *   D5 (GPIO14) -> SCK
 *   D7 (GPIO13) -> MOSI
 *   D6 (GPIO12) -> MISO
 *   D3 (GPIO0)  -> RST
 *   3V3         -> 3.3V   (NOT 5V — RC522 is 3.3V only)
 *   GND         -> GND
 *
 * Libraries (Arduino IDE -> Library Manager):
 *   - "MFRC522" by GithubCommunity
 *   - ESP8266 board package (Boards Manager URL:
 *     http://arduino.esp8266.com/stable/package_esp8266com_index.json)
 */

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <SPI.h>
#include <MFRC522.h>

// ── CONFIG — edit these ────────────────────────────────────────
const char* WIFI_SSID     = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

const char* SERVER_HOST   = "attendance-rfid.onrender.com";
const char* TAP_PATH      = "/api/v1/rfid/tap";
const char* API_KEY       = "YOUR_API_KEY"; // must match CAMERA_API_KEY on the server
const char* READER_ID     = "main-entrance";

// ── Pins ───────────────────────────────────────────────────────
#define SS_PIN   15   // D8
#define RST_PIN  0    // D3
#define LED_PIN  2    // onboard LED (active LOW)

MFRC522 rfid(SS_PIN, RST_PIN);

unsigned long lastKeepAlive   = 0;
const unsigned long KEEPALIVE_MS = 10UL * 60UL * 1000UL; // ping every 10 min
String lastUid                = "";
unsigned long lastTapMs       = 0;
const unsigned long DEBOUNCE_MS = 5000; // ignore same card for 5 s

void blink(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, LOW);  delay(ms);
    digitalWrite(LED_PIN, HIGH); delay(ms);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

  SPI.begin();
  rfid.PCD_Init();

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi OK: " + WiFi.localIP().toString());
  blink(2, 100);
}

String readUid() {
  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
    if (i < rfid.uid.size - 1) uid += ":";
  }
  uid.toUpperCase();
  return uid;
}

// Returns HTTP status code, or -1 on connection failure
int postTap(const String& uid) {
  WiFiClientSecure client;
  client.setInsecure();              // skip TLS cert validation
  client.setTimeout(20000);          // Render free tier can be slow to wake

  HTTPClient https;
  https.setTimeout(20000);
  if (!https.begin(client, String("https://") + SERVER_HOST + TAP_PATH)) return -1;

  https.addHeader("Content-Type", "application/json");
  https.addHeader("X-Camera-Key", API_KEY);

  String body = String("{\"card_uid\":\"") + uid +
                "\",\"reader_id\":\"" + READER_ID + "\"}";
  int code = https.POST(body);
  if (code > 0) {
    Serial.printf("HTTP %d: %s\n", code, https.getString().c_str());
  } else {
    Serial.printf("POST failed: %s\n", https.errorToString(code).c_str());
  }
  https.end();
  return code;
}

void keepAlive() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;
  if (https.begin(client, String("https://") + SERVER_HOST + "/health")) {
    https.GET();
    https.end();
  }
}

void loop() {
  // Keep the Render service awake so taps respond instantly
  if (millis() - lastKeepAlive > KEEPALIVE_MS) {
    lastKeepAlive = millis();
    keepAlive();
  }

  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return;

  String uid = readUid();
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  // Debounce: same card within 5 s -> ignore
  if (uid == lastUid && millis() - lastTapMs < DEBOUNCE_MS) return;
  lastUid   = uid;
  lastTapMs = millis();

  Serial.println("Card: " + uid);
  digitalWrite(LED_PIN, LOW); // LED on while sending

  int code = postTap(uid);
  if (code == 200) {
    blink(1, 400);        // long blink = OK (clock in/out or registered)
  } else if (code == -1) {
    int retry = postTap(uid);   // one retry (server may have been waking up)
    blink(retry == 200 ? 1 : 5, retry == 200 ? 400 : 80);
  } else {
    blink(5, 80);         // rapid blinks = error (check Serial monitor)
  }
  digitalWrite(LED_PIN, HIGH);
}
