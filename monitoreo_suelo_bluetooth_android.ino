/*
  FIRMWARE BLUETOOTH - Monitoreo de Suelo  (MAPA DE REGISTROS CONFIRMADO)
  ESP32 + sensor 7en1 (Modbus RTU / RS485). Toma 5 muestras, promedia y envia
  UNA linea JSON por Bluetooth CLASICO (SPP) a la app Flutter ("ESP32_Suelo").

  MAPA DE REGISTROS:
    - Humedad      = 0x0012  / 10    VALIDADO (seco ~10%, mojado ~73%)
    - CE (µS/cm)   = 0x0015  crudo   VALIDADO (0 en seco, topa 10000 en salado => CRITICO)
    - pH           = 0x0006  / 100   (~6.10)
    - Temperatura  = 0x0007  / 100   REFERENCIAL (~26°C). El companiero NO uso ni
                     valido la temperatura, asi que su 0x0013 no era confiable.
                     0x0007/100 da valores mas razonables; falta calibrar bien
                     con un termometro. No es critico: el clasificador casi no la usa.
    - NPK          = 0x001E/0x001F/0x0020 (no se usan en la app por ahora)

  NOTA: los registros estan dispersos, por eso se lee cada grupo por separado
  (una lectura contigua grande falla porque hay direcciones inexistentes en medio).

  Se mantiene Bluetooth CLASICO (SPP) + JSON para no romper la app. El codigo del
  companiero usa BLE; NO se copia su transporte, solo su mapa de registros.
*/
#include <ModbusMaster.h>
#include "BluetoothSerial.h"

#if !defined(CONFIG_BT_ENABLED) || !defined(CONFIG_BLUEDROID_ENABLED)
#error Bluetooth no habilitado. Usa una placa ESP32 con Bluetooth clasico.
#endif

// ---------- Pines / Modbus ----------
#define PIN_DE_RE      4
#define PIN_RX2        16
#define PIN_TX2        17
#define MODBUS_ID      1
#define BAUDIOS_SENSOR 9600

// ---------- Registros ----------
#define REG_HUMEDAD    0x0012    // qty 1: humedad (/10)   VALIDADO
#define REG_TEMP       0x0007    // qty 1: temperatura (/100)  REFERENCIAL
#define REG_CE         0x0015    // qty 1: CE crudo (µS/cm)    VALIDADO
#define REG_PH         0x0006    // qty 1: pH (/100)

#define ESC_HUMEDAD      10.0    // crudo/10  -> %
#define ESC_TEMPERATURA  100.0   // crudo/100 -> °C
#define ESC_CE           1.0     // crudo     -> µS/cm
#define ESC_PH           100.0   // crudo/100 -> pH

// ---------- Promedio ----------
#define N_MUESTRAS        5
#define MS_ENTRE_MUESTRAS 250
#define PERIODO_MS        2000

#define NOMBRE_BT   "ESP32_Suelo"
#define PUNTO       "P1"

ModbusMaster nodo;
BluetoothSerial SerialBT;

void preTransmision()  { digitalWrite(PIN_DE_RE, HIGH); }
void postTransmision() { digitalWrite(PIN_DE_RE, LOW);  }

void enviar(const String& s) { SerialBT.println(s); Serial.println(s); }

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(PIN_DE_RE, OUTPUT);
  digitalWrite(PIN_DE_RE, LOW);
  Serial2.begin(BAUDIOS_SENSOR, SERIAL_8N1, PIN_RX2, PIN_TX2);
  nodo.begin(MODBUS_ID, Serial2);
  nodo.preTransmission(preTransmision);
  nodo.postTransmission(postTransmision);

  SerialBT.begin(NOMBRE_BT);
  Serial.println("\n== Firmware BT (mapa confirmado) listo. Empareja \"" NOMBRE_BT "\" y conecta. ==");
}

// Lee los 4 registros una vez. Devuelve true si TODO salio bien.
bool leerUnaVez(uint16_t &hum, uint16_t &temp, uint16_t &ce, uint16_t &ph) {
  bool ok = true;

  if (nodo.readHoldingRegisters(REG_HUMEDAD, 1) == nodo.ku8MBSuccess) {
    hum = nodo.getResponseBuffer(0);    // 0x0012
  } else ok = false;

  if (nodo.readHoldingRegisters(REG_TEMP, 1) == nodo.ku8MBSuccess) {
    temp = nodo.getResponseBuffer(0);   // 0x0007
  } else ok = false;

  if (nodo.readHoldingRegisters(REG_CE, 1) == nodo.ku8MBSuccess) {
    ce = nodo.getResponseBuffer(0);     // 0x0015
  } else ok = false;

  if (nodo.readHoldingRegisters(REG_PH, 1) == nodo.ku8MBSuccess) {
    ph = nodo.getResponseBuffer(0);     // 0x0006
  } else ok = false;

  return ok;
}

void loop() {
  long sHum = 0, sTemp = 0, sCE = 0, sPH = 0;
  uint8_t ok = 0;

  for (uint8_t i = 0; i < N_MUESTRAS; i++) {
    uint16_t h = 0, t = 0, c = 0, p = 0;
    if (leerUnaVez(h, t, c, p)) {
      sHum += h; sTemp += t; sCE += c; sPH += p;
      ok++;
    }
    delay(MS_ENTRE_MUESTRAS);
  }

  if (ok > 0) {
    float humedad     = (sHum  / (float)ok) / ESC_HUMEDAD;
    float temperatura = (sTemp / (float)ok) / ESC_TEMPERATURA;
    float ce          = (sCE   / (float)ok) / ESC_CE;
    float ph          = (sPH   / (float)ok) / ESC_PH;

    String j = "{";
    j += "\"punto\":\"" PUNTO "\",";
    j += "\"humedad\":"     + String(humedad, 1) + ",";
    j += "\"temperatura\":" + String(temperatura, 1) + ",";
    j += "\"ph\":"          + String(ph, 2) + ",";
    j += "\"ce\":"          + String(ce, 0) + ",";
    j += "\"n_lecturas\":"  + String(ok) + "}";
    enviar(j);
  } else {
    enviar("{\"estado\":\"error\",\"mensaje\":\"sin respuesta del sensor\"}");
  }

  delay(PERIODO_MS);
}
