// Genera CAPTURAS de la UI sin necesidad de un dispositivo conectado.
//
// Renderiza las pantallas a tamaño de teléfono y las guarda como PNG usando el
// mecanismo de "golden files". Para (re)generar las imágenes:
//
//   flutter test --update-goldens test/preview_test.dart
//
// Las imágenes quedan en test/goldens/. No es una prueba de regresión real;
// es solo una utilidad para previsualizar el diseño.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/main.dart';
import 'package:monitoreo_suelo/modelos/medicion.dart';
import 'package:monitoreo_suelo/pantallas/historial.dart';

// Carpeta de fuentes que trae el SDK de Flutter (Roboto + Material Icons).
const _fonts = r'C:/src/flutter/bin/cache/artifacts/material_fonts';

Future<ByteData> _leer(String ruta) async =>
    ByteData.sublistView(await File(ruta).readAsBytes());

Future<void> _cargarFuentes() async {
  await (FontLoader('Roboto')
        ..addFont(_leer('$_fonts/roboto-regular.ttf'))
        ..addFont(_leer('$_fonts/roboto-medium.ttf'))
        ..addFont(_leer('$_fonts/roboto-bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(_leer('$_fonts/materialicons-regular.otf'))).load();
  // En el render de prueba no hay fuente "monospace" del sistema; la mapeamos
  // a Roboto solo para que la línea de depuración salga legible (en el teléfono
  // real sí existe la monospace del sistema).
  await (FontLoader(
    'monospace',
  )..addFont(_leer('$_fonts/roboto-regular.ttf'))).load();
}

ThemeData _tema() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
  scaffoldBackgroundColor: const Color(0xFFF5F7F4),
  fontFamily: 'Roboto',
);

Future<void> _capturar(
  WidgetTester tester,
  Widget home,
  String archivo, {
  double alto = 800,
}) async {
  // Tamaño lógico tipo teléfono (≈ Samsung S23) con densidad 2x.
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(360 * 2, alto * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(debugShowCheckedModeBanner: false, theme: _tema(), home: home),
  );
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$archivo'),
  );
}

void main() {
  setUpAll(_cargarFuentes);

  testWidgets('captura: conectado, condición normal', (tester) async {
    await _capturar(
      tester,
      const PantallaLecturas(
        datosDemo: {
          'dispositivo': 'ESP32_Suelo',
          'conectado': true,
          'estado': 'Conectado a ESP32_Suelo',
          'punto': 'P1',
          'humedad': 56.0,
          'temperatura': 23.8,
          'ce': 40,
          'ph': 6.8,
          'n_lecturas': 5,
          'guardadas': 3,
          'crudo':
              '{"punto":"P1","humedad":56.0,"temperatura":23.8,"ph":6.8,"ce":40,"n_lecturas":5}',
        },
      ),
      'conectado.png',
    );
  });

  testWidgets('captura: condición crítica con alerta preventiva', (
    tester,
  ) async {
    await _capturar(
      tester,
      const PantallaLecturas(
        datosDemo: {
          'dispositivo': 'ESP32_Suelo',
          'conectado': true,
          'estado': 'Conectado a ESP32_Suelo',
          'punto': 'P3',
          'humedad': 88.0,
          'temperatura': 41.0,
          'ce': 6200,
          'ph': 6.8,
          'n_lecturas': 5,
          'crudo':
              '{"punto":"P3","humedad":88.0,"temperatura":41.0,"ph":6.8,"ce":6200,"n_lecturas":5}',
        },
      ),
      'critico.png',
      alto: 940,
    );
  });

  testWidgets('captura: desconectado (pantalla inicial)', (tester) async {
    await _capturar(
      tester,
      const PantallaLecturas(
        datosDemo: {'conectado': false, 'estado': 'Desconectado'},
      ),
      'desconectado.png',
    );
  });

  testWidgets('captura: historial con registros', (tester) async {
    await _capturar(
      tester,
      PantallaHistorial(
        demo: [
          Medicion(
            id: 3,
            terreno: 'Terreno A',
            punto: 'P1',
            fechaHora: '2026-06-29T10:15:00',
            humedad: 68.3,
            temperatura: 24.6,
            ce: 1459,
            nLecturas: 5,
            observaciones: 'Suelo húmedo tras riego',
            condicion: 'normal',
          ),
          Medicion(
            id: 2,
            terreno: 'Terreno A',
            punto: 'P2',
            fechaHora: '2026-06-29T10:05:00',
            humedad: 41.2,
            temperatura: 27.1,
            ce: 980,
            nLecturas: 5,
            condicion: 'moderado',
          ),
          Medicion(
            id: 1,
            terreno: 'Terreno B',
            punto: 'P1',
            fechaHora: '2026-06-28T16:40:00',
            humedad: 23.7,
            temperatura: 31.4,
            ce: 610,
            nLecturas: 4,
            observaciones: 'Zona seca, sin sombra',
            condicion: 'crítico',
          ),
        ],
      ),
      'historial.png',
    );
  });
}
