# Firmware de la ESP32 (sensor de suelo 7 en 1)

Sketches de Arduino para la ESP32 que lee el sensor 7-en-1 por **Modbus RTU / RS485**.

## Carpetas

- **`firmware_bluetooth/`** — Firmware **principal**. Lee el sensor y envía una línea
  JSON por **Bluetooth clásico (SPP)** con el nombre `ESP32_Suelo`, que es lo que
  consume la app Flutter. Formato:
  `{"punto":"P1","humedad":68.3,"temperatura":24.6,"ph":6.8,"ce":1459,"n_lecturas":1}`
  y, si el sensor no responde:
  `{"estado":"error","mensaje":"sin respuesta del sensor"}`.
- **`diagnostico_registros/`** — Utilidad para **descubrir/validar el mapa de registros**
  del sensor (cuál es humedad, temperatura, pH, CE) volcando los valores crudos por USB.

## Conexiones (ambos sketches)

| Señal            | Pin ESP32 |
|------------------|-----------|
| RS485 DE/RE      | GPIO 4    |
| RS485 RO → RX2   | GPIO 16   |
| RS485 DI → TX2   | GPIO 17   |
| Sensor (Modbus)  | ID 1, 9600 bps, registros 0x0006–0x000C |

> El sensor necesita su alimentación de **12 V** (con **GND común** entre ESP32,
> módulo RS485, sensor y la fuente de 12 V). Sin 12 V, el sensor no responde y se
> ve `Error Modbus 0xE2` (timeout).

## Cómo flashear

1. Arduino IDE → abre el `.ino` de la carpeta que quieras subir.
2. **Tools → Board:** *ESP32 Dev Module* · **Port:** el COM de la ESP32.
3. **Upload** (si se traba en "Connecting…", mantén pulsado **BOOT**).
4. Si "Sketch too big" (solo el de Bluetooth): **Tools → Partition Scheme → Huge APP (3MB No OTA)**.
5. Requiere la librería **ModbusMaster** y el core de **ESP32** (trae `BluetoothSerial`).

## Pendiente de calibración

El **mapa de registros** en `firmware_bluetooth` es una estimación inicial. Confírmalo
con `diagnostico_registros` (prueba seco/húmedo) y ajusta los `IDX_*` y `ESC_*`.
La temperatura (÷100 ≈ 24 °C) es la más confiable; **verifica la humedad** metiendo la
sonda en agua y viendo qué registro sube fuerte.
