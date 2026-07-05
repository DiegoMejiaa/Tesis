// Verifica, SIN dispositivo, que el historial muestra la miniatura de la foto
// cuando la medición tiene una y que al tocarla se abre el visor a pantalla
// completa. Usa una imagen PNG real de 1x1 en un archivo temporal.
//
//   flutter test test/foto_historial_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/modelos/medicion.dart';
import 'package:monitoreo_suelo/pantallas/historial.dart';

// PNG transparente de 1x1 (mínimo válido) para tener un archivo de imagen real.
const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory tmp;
  late String rutaFoto;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hist_foto_');
    final f = File('${tmp.path}/foto.png');
    await f.writeAsBytes(base64Decode(_png1x1Base64));
    rutaFoto = f.path;
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Medicion medicion({String? foto}) => Medicion(
        id: 1,
        terreno: 'Terreno A',
        punto: 'P1',
        fechaHora: '2026-06-29T10:00:00',
        humedad: 60,
        temperatura: 24,
        ce: 900,
        condicion: 'normal',
        foto: foto,
      );

  testWidgets('muestra la miniatura y abre el visor al tocarla',
      (tester) async {
    await _pump(tester, PantallaHistorial(demo: [medicion(foto: rutaFoto)]));

    // Hay exactamente una imagen (la miniatura de la foto del punto).
    expect(find.byType(Image), findsOneWidget);

    // Al tocarla se navega al visor a pantalla completa.
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.text('Foto del punto'), findsOneWidget);
  });

  testWidgets('sin foto no se renderiza miniatura', (tester) async {
    await _pump(tester, PantallaHistorial(demo: [medicion()]));
    expect(find.byType(Image), findsNothing);
  });
}
