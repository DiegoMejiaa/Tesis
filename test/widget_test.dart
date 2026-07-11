// Smoke test: la pantalla principal se construye y muestra las lecturas.
// Usa el "modo demo" (datosDemo) para no depender de Bluetooth ni de SQLite.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/main.dart';

void main() {
  testWidgets('La pantalla principal muestra título y lecturas', (
    tester,
  ) async {
    // Viewport alto (y ancho como el de por defecto) para que el ListView
    // construya todo el contenido, incluido el botón al final del scroll.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: PantallaLecturas(
          datosDemo: {
            'dispositivo': 'ESP32_Suelo',
            'conectado': true,
            'estado': 'Conectado a ESP32_Suelo',
            'punto': 'P1',
            'humedad': 68.3,
            'temperatura': 24.6,
            'ce': 1459,
            'ph': 6.8,
            'n_lecturas': 5,
            'guardadas': 3,
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Monitoreo de Suelo'), findsOneWidget);
    expect(find.text('Humedad'), findsOneWidget);
    expect(find.text('Temperatura'), findsOneWidget);
    expect(find.text('Conductividad'), findsOneWidget);
    expect(find.text('pH'), findsOneWidget);
    expect(find.textContaining('68.3'), findsOneWidget);
    expect(find.textContaining('6.8'), findsOneWidget);
    // El botón "Guardar medición" debe estar presente (hay lecturas).
    expect(find.text('Guardar medición'), findsOneWidget);

    // n_lecturas se rotula como "promedio de muestras", NO como un contador.
    expect(find.text('Punto P1 · promedio de 5 muestras'), findsOneWidget);
    expect(find.textContaining('5 lecturas'), findsNothing);
    // El contador REAL de mediciones guardadas se muestra aparte.
    expect(find.text('Guardadas en este punto: 3'), findsOneWidget);
  });
}
