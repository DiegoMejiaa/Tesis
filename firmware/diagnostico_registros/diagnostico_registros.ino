/*
  =====================================================================
  DIAGNOSTICO DE REGISTROS - Sensor de suelo 7 en 1 (Modbus RTU)
  ---------------------------------------------------------------------
  Objetivo: ver los VALORES CRUDOS de cada registro para descubrir el
  mapa real de TU sensor (cual registro es humedad, temperatura, pH y
  conductividad) y los factores de escala correctos.

  Mismas conexiones que el codigo principal. Solo sube este sketch,
  abre el Monitor Serial a 115200 y observa la tabla.

  COMO USARLO (validacion de coherencia fisica - seco vs humedo):
   1) Con el sensor en suelo SECO, anota los 7 valores crudos.
   2) Moja el suelo (o mete el sensor en suelo humedo) y observa cuales
      cambian. El registro que SUBE fuerte con el agua = HUMEDAD.
   3) Toca/calienta el sensor: el registro que cambia despacio = TEMPERATURA.
   4) Asi identificas cada variable sin depender de un mapa generico.
  =====================================================================
*/

#include <ModbusMaster.h>

#define PIN_DE_RE      4
#define PIN_RX2        16
#define PIN_TX2        17
#define MODBUS_ID      1
#define BAUDIOS_SENSOR 9600

#define REG_INICIO     0x0006
#define CANT_REG       7        // lee 0x0006 .. 0x000C

ModbusMaster nodo;

void preTransmision()  { digitalWrite(PIN_DE_RE, HIGH); }
void postTransmision() { digitalWrite(PIN_DE_RE, LOW);  }

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(PIN_DE_RE, OUTPUT);
  digitalWrite(PIN_DE_RE, LOW);
  Serial2.begin(BAUDIOS_SENSOR, SERIAL_8N1, PIN_RX2, PIN_TX2);
  nodo.begin(MODBUS_ID, Serial2);
  nodo.preTransmission(preTransmision);
  nodo.postTransmission(postTransmision);
  Serial.println("\n== DIAGNOSTICO DE REGISTROS (0x0006 a 0x000C) ==");
  Serial.println("Reg     | crudo | /10    | /100");
}

void loop() {
  uint8_t r = nodo.readHoldingRegisters(REG_INICIO, CANT_REG);

  if (r == nodo.ku8MBSuccess) {
    Serial.println("-----------------------------------------");
    for (int i = 0; i < CANT_REG; i++) {
      uint16_t crudo = nodo.getResponseBuffer(i);
      int reg = REG_INICIO + i;
      Serial.print("0x000");
      Serial.print(reg, HEX);
      Serial.print(" | ");
      Serial.print(crudo);
      Serial.print("\t | ");
      Serial.print(crudo / 10.0, 1);
      Serial.print("\t | ");
      Serial.println(crudo / 100.0, 2);
    }
  } else {
    Serial.print("Error Modbus 0x");
    Serial.println(r, HEX);
  }

  delay(2000);
}
