// Pruebas del motor de clasificación difusa (Módulo 3). Lógica pura: no
// requiere sensor, teléfono ni base de datos.
//
//   flutter test test/clasificador_difuso_test.dart
//
// Umbrales de CE ALINEADOS A CORROSIVIDAD del suelo (aplicación a obras
// civiles), no a salinidad agrícola. Escala de referencia: resistividad
// (NACE SP0169; AWWA C105/A21.5; Romanoff, NBS Circular 579), convertida a
// CE con resistividad(Ω·cm) = 1e6 / CE(µS/cm). Cruces de clase en 100 µS/cm
// (10 000 Ω·cm, no/levemente -> moderado) y 333 µS/cm (3 000 Ω·cm,
// corrosivo -> altamente corrosivo). Banda de humedad "alta" >=80 %.

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/clasificador_difuso.dart';

void main() {
  // Regresión: un suelo real de campo (seco, CE baja ~82 µS/cm) debe salir
  // NORMAL. En la escala de corrosividad, CE 82 µS/cm ≈ 12 200 Ω·cm =
  // levemente corrosivo -> normal. (Datos reales del Terreno 1, punto P8.)
  test('suelo de campo real (CE ~82, seco) -> normal', () {
    final c = clasificar(humedad: 9.9, ce: 82, temperatura: 24);
    expect(c.categoria, 'normal');
    expect(c.score, lessThan(40));
    expect(c.variablesAlteradas, isEmpty);
  });

  // CE 500 µS/cm ≈ 2 000 Ω·cm = altamente corrosivo -> crítico.
  test('CE 500 (altamente corrosivo) -> crítico', () {
    final c = clasificar(humedad: 45, ce: 500, temperatura: 24);
    expect(c.categoria, 'crítico');
    expect(c.score, greaterThan(60));
    expect(c.variablesAlteradas, contains('Conductividad (CE) alta'));
  });

  // CE 200 µS/cm ≈ 5 000 Ω·cm = moderadamente corrosivo -> moderado.
  test('CE 200 (moderadamente corrosivo) -> moderado', () {
    final c = clasificar(humedad: 45, ce: 200, temperatura: 24);
    expect(c.categoria, 'moderado');
    expect(c.score, inInclusiveRange(40, 60));
  });

  // CE extrema (agua con sal, ensayo controlado) -> crítico.
  test('CE ~5180 (extremadamente corrosivo) -> crítico', () {
    final c = clasificar(humedad: 50, ce: 5180, temperatura: 25);
    expect(c.categoria, 'crítico');
    expect(c.score, greaterThan(60));
    expect(c.variablesAlteradas, contains('Conductividad (CE) alta'));
  });

  // CE 50 µS/cm ≈ 20 000 Ω·cm = esencialmente no corrosivo -> normal.
  test('CE baja no corrosiva + humedad media -> normal', () {
    final c = clasificar(humedad: 45, ce: 50, temperatura: 24);
    expect(c.categoria, 'normal');
    expect(c.score, lessThan(40));
    expect(c.variablesAlteradas, isEmpty);
  });

  // Humedad alta agrava una CE en banda "media" (moderada) a crítico.
  test('CE media + humedad alta -> crítico', () {
    final c = clasificar(humedad: 85, ce: 200, temperatura: 24);
    expect(c.categoria, 'crítico');
  });

  test('temperatura alta + CE media agrava la condición a crítico', () {
    final base = clasificar(humedad: 45, ce: 200, temperatura: 24); // moderado
    final agravado = clasificar(humedad: 45, ce: 200, temperatura: 42);
    expect(agravado.score, greaterThan(base.score));
    expect(agravado.categoria, 'crítico');
    expect(agravado.variablesAlteradas, contains('Temperatura alta'));
  });

  test('transición suave: el score no decrece al subir la CE', () {
    double previo = -1;
    for (final ce in [50.0, 200.0, 500.0, 1000.0, 5000.0, 10000.0]) {
      final s = clasificar(humedad: 45, ce: ce, temperatura: 24).score;
      expect(s, greaterThanOrEqualTo(previo - 0.01));
      previo = s;
    }
  });

  test('variablesAlteradas detecta los tres extremos (>0.5)', () {
    final c = clasificar(humedad: 90, ce: 5000, temperatura: 45);
    expect(
      c.variablesAlteradas,
      containsAll(
          ['Conductividad (CE) alta', 'Humedad alta', 'Temperatura alta']),
    );
  });

  test('sin temperatura no rompe (factor agravante desactivado)', () {
    final c = clasificar(humedad: 50, ce: 150);
    expect(c.categoria, isNotEmpty);
    expect(c.variablesAlteradas, isNot(contains('Temperatura alta')));
  });

  test('score siempre dentro de 0..100', () {
    for (final ce in [0.0, 200.0, 12000.0]) {
      for (final h in [0.0, 50.0, 100.0]) {
        final s = clasificar(humedad: h, ce: ce, temperatura: 25).score;
        expect(s, inInclusiveRange(0, 100));
      }
    }
  });
}
