/*
  FIRMWARE BLUETOOTH - Monitoreo de Suelo
  ESP32 + sensor 7en1 (Modbus RTU / RS485). Lee el sensor y envía UNA línea
  JSON por Bluetooth clásico (SPP) que la app Flutter ("ESP32_Suelo") interpreta.
  Mismos pines/Modbus que el sketch de diagnóstico.
*/
#include <ModbusMaster.h>
#include "BluetoothSerial.h"

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error Bluetooth no habilitado. Usa una placa ESP32 con Bluetooth clásico.
#endif

// ---------- Pines / Modbus (idénticos al diagnóstico) ----------
#define PIN_DE_RE      4
#define PIN_RX2        16
#define PIN_TX2        17
#define MODBUS_ID      1
#define BAUDIOS_SENSOR 9600
#define REG_INICIO     0x0006
#define CANT_REG       7          // 0x0006 .. 0x000C
#define REG_TEMP       0x0013

// ---------- MAPA DE REGISTROS (índice = registro - 0x0006) ----------
// !!! VERIFICA con la prueba seco/húmedo y ajusta si hace falta.
// La temperatura se lee aparte en 0x0013 y se escala con /10.
#define IDX_HUMEDAD      0        // 0x0006  (mete la sonda en agua: la que SUBE fuerte)
#define IDX_CE           2        // 0x0008  (conductividad, µS/cm)
#define IDX_PH           3        // 0x0009
#define ESC_HUMEDAD      10.0     // crudo/10  -> %
#define ESC_TEMPERATURA  10.0     // crudo/10 -> °C
#define ESC_CE           1.0      // crudo     -> µS/cm
#define ESC_PH           100.0    // crudo/100 -> pH

#define NOMBRE_BT   "ESP32_Suelo"
#define PUNTO       "P1"
#define PERIODO_MS  2000

ModbusMaster nodo;
BluetoothSerial SerialBT;

void preTransmision()  { digitalWrite(PIN_DE_RE, HIGH); }
void postTransmision() { digitalWrite(PIN_DE_RE, LOW);  }

void enviar(const String& s) { SerialBT.println(s); Serial.println(s); } // BT + USB

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(PIN_DE_RE, OUTPUT);
  digitalWrite(PIN_DE_RE, LOW);
  Serial2.begin(BAUDIOS_SENSOR, SERIAL_8N1, PIN_RX2, PIN_TX2);
  nodo.begin(MODBUS_ID, Serial2);
  nodo.preTransmission(preTransmision);
  nodo.postTransmission(postTransmision);

  // Bluetooth SIEMPRE arranca, aunque el sensor falle.
  SerialBT.begin(NOMBRE_BT);
  Serial.println("\n== Firmware BT iniciado. Empareja \"" NOMBRE_BT "\" y conecta. ==");
}

void loop() {
  uint8_t r = nodo.readHoldingRegisters(REG_INICIO, CANT_REG);

  if (r == nodo.ku8MBSuccess) {
    uint16_t rawHumedad = nodo.getResponseBuffer(IDX_HUMEDAD);
    uint16_t rawCe      = nodo.getResponseBuffer(IDX_CE);
    uint16_t rawPh      = nodo.getResponseBuffer(IDX_PH);

    uint8_t rt = nodo.readHoldingRegisters(REG_TEMP, 1);
    if (rt != nodo.ku8MBSuccess) {
      enviar("{\"estado\":\"error\",\"mensaje\":\"sin respuesta del sensor\"}");
      delay(PERIODO_MS);
      return;
    }

    float humedad     = rawHumedad / ESC_HUMEDAD;
    float temperatura = nodo.getResponseBuffer(0) / ESC_TEMPERATURA;
    float ce          = rawCe / ESC_CE;
    float ph          = rawPh / ESC_PH;

    String j = "{";
    j += "\"punto\":\"" PUNTO "\",";
    j += "\"humedad\":"     + String(humedad, 1) + ",";
    j += "\"temperatura\":" + String(temperatura, 1) + ",";
    j += "\"ph\":"          + String(ph, 2) + ",";
    j += "\"ce\":"          + String(ce, 0) + ",";
    j += "\"n_lecturas\":1}";
    enviar(j);
  } else {
    enviar("{\"estado\":\"error\",\"mensaje\":\"sin respuesta del sensor\"}");
  }
  delay(PERIODO_MS);
}
