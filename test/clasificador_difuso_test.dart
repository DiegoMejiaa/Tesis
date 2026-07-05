// Pruebas del motor de clasificación difusa (Módulo 3). Lógica pura: no
// requiere sensor, teléfono ni base de datos.
//
//   flutter test test/clasificador_difuso_test.dart
//
// Umbrales PRELIMINARES: CE alineada a las clases de salinidad USDA-NRCS
// (no salino <2000, ligeramente salino 2000–4000, salino >4000 µS/cm) y
// banda de humedad "alta" >=80 %, pendientes de criterio experto.

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/clasificador_difuso.dart';

void main() {
  // Caso de regresión del bug reportado: una tierra común (CE ~1400 µS/cm,
  // humedad ~65-70 %) NO debe salir crítico. Con la CE alineada a USDA-NRCS
  // (no salino) y la humedad ~68 % dentro de la banda "media", sale normal.
  test('tierra común (CE ~1400, humedad ~68) -> normal', () {
    final c = clasificar(humedad: 68, ce: 1400, temperatura: 24);
    expect(c.categoria, 'normal');
    expect(c.score, lessThan(40));
    expect(c.variablesAlteradas, isEmpty);
  });

  test('CE 5000 (salino) -> crítico', () {
    final c = clasificar(humedad: 50, ce: 5000, temperatura: 24);
    expect(c.categoria, 'crítico');
    expect(c.score, greaterThan(60));
  });

  test('CE ~3000 + humedad ~50 (caso intermedio) -> moderado', () {
    final c = clasificar(humedad: 50, ce: 3000, temperatura: 24);
    expect(c.categoria, 'moderado');
    expect(c.score, inInclusiveRange(40, 60));
  });

  test('CE alta -> crítico', () {
    final c = clasificar(humedad: 50, ce: 6000, temperatura: 25);
    expect(c.categoria, 'crítico');
    expect(c.score, greaterThan(60));
    expect(c.variablesAlteradas, contains('Conductividad (CE) alta'));
  });

  test('CE baja + humedad media -> normal', () {
    final c = clasificar(humedad: 45, ce: 400, temperatura: 24);
    expect(c.categoria, 'normal');
    expect(c.score, lessThan(40));
    expect(c.variablesAlteradas, isEmpty);
  });

  test('CE media + humedad alta -> crítico', () {
    final c = clasificar(humedad: 85, ce: 2500, temperatura: 24);
    expect(c.categoria, 'crítico');
  });

  test('temperatura alta + CE media agrava la condición a crítico', () {
    final base = clasificar(humedad: 45, ce: 3000, temperatura: 24); // moderado
    final agravado = clasificar(humedad: 45, ce: 3000, temperatura: 42);
    expect(agravado.score, greaterThan(base.score));
    expect(agravado.categoria, 'crítico');
    expect(agravado.variablesAlteradas, contains('Temperatura alta'));
  });

  test('transición suave: el score no decrece al subir la CE', () {
    double previo = -1;
    for (final ce in [200.0, 1000.0, 2000.0, 3000.0, 5000.0, 8000.0]) {
      final s = clasificar(humedad: 45, ce: ce, temperatura: 24).score;
      expect(s, greaterThanOrEqualTo(previo - 0.01));
      previo = s;
    }
  });

  test('variablesAlteradas detecta los tres extremos (>0.5)', () {
    final c = clasificar(humedad: 90, ce: 6000, temperatura: 45);
    expect(
      c.variablesAlteradas,
      containsAll(
          ['Conductividad (CE) alta', 'Humedad alta', 'Temperatura alta']),
    );
  });

  test('sin temperatura no rompe (factor agravante desactivado)', () {
    final c = clasificar(humedad: 50, ce: 700);
    expect(c.categoria, isNotEmpty);
    expect(c.variablesAlteradas, isNot(contains('Temperatura alta')));
  });

  test('score siempre dentro de 0..100', () {
    for (final ce in [0.0, 1500.0, 12000.0]) {
      for (final h in [0.0, 50.0, 100.0]) {
        final s = clasificar(humedad: h, ce: ce, temperatura: 25).score;
        expect(s, inInclusiveRange(0, 100));
      }
    }
  });
}
