// Verifica el contador REAL de mediciones guardadas por punto/terreno
// (Módulo 2). Es lógica pura: no depende de Bluetooth ni de SQLite.
//
//   flutter test test/contador_guardadas_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/contador_guardadas.dart';

void main() {
  test('empieza en 0', () {
    expect(ContadorGuardadas().cuenta, 0);
  });

  test('sube 1 por cada medición guardada en el mismo punto', () {
    final c = ContadorGuardadas();
    expect(c.registrar('Terreno A', 'P1'), 1);
    expect(c.registrar('Terreno A', 'P1'), 2);
    expect(c.registrar('Terreno A', 'P1'), 3);
    expect(c.cuenta, 3);
  });

  test('se reinicia al cambiar de punto', () {
    final c = ContadorGuardadas();
    c.registrar('Terreno A', 'P1');
    c.registrar('Terreno A', 'P1');
    expect(c.cuenta, 2);
    expect(c.registrar('Terreno A', 'P2'), 1); // punto nuevo -> vuelve a 1
    expect(c.cuenta, 1);
  });

  test('se reinicia al cambiar de terreno aunque el punto se llame igual', () {
    final c = ContadorGuardadas();
    c.registrar('Terreno A', 'P1');
    c.registrar('Terreno A', 'P1');
    expect(c.cuenta, 2);
    expect(c.registrar('Terreno B', 'P1'), 1); // otro terreno -> vuelve a 1
    expect(c.cuenta, 1);
  });

  test('volver a un punto anterior NO recuerda su conteo (arranca de nuevo)', () {
    final c = ContadorGuardadas();
    c.registrar('Terreno A', 'P1');
    c.registrar('Terreno A', 'P1'); // P1 va en 2
    c.registrar('Terreno A', 'P2'); // cambia a P2 -> 1
    expect(c.registrar('Terreno A', 'P1'), 1); // regresar a P1 reinicia
  });

  test('reiniciar() deja el contador en 0', () {
    final c = ContadorGuardadas();
    c.registrar('Terreno A', 'P1');
    c.registrar('Terreno A', 'P1');
    c.reiniciar();
    expect(c.cuenta, 0);
    expect(c.registrar('Terreno A', 'P1'), 1); // tras reiniciar, arranca en 1
  });
}
