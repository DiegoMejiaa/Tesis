// Verifica el generador del reporte PDF (Módulo 5) SIN dispositivo: el PDF se
// arma con el paquete `pdf` (Dart puro), así que se puede probar en el PC.
//
//   flutter test test/reporte_pdf_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/reporte_pdf.dart';
import 'package:monitoreo_suelo/modelos/medicion.dart';

Medicion _m({
  required String terreno,
  required String punto,
  String observaciones = '',
  double? humedad,
  double? ce,
  String? condicion,
}) =>
    Medicion(
      terreno: terreno,
      punto: punto,
      fechaHora: '2026-06-29T10:00:00',
      humedad: humedad,
      ce: ce,
      observaciones: observaciones,
      condicion: condicion,
    );

void main() {
  test('grupoDe: campo por defecto, controles y banco por palabra clave', () {
    expect(grupoDe(_m(terreno: 'Terreno A', punto: 'P1')), GrupoMuestreo.campo);
    expect(grupoDe(_m(terreno: 'Punto de control', punto: 'C1')),
        GrupoMuestreo.controles);
    expect(grupoDe(_m(terreno: 'Banco de préstamo', punto: 'B1')),
        GrupoMuestreo.banco);
    // La pista puede venir en observaciones.
    expect(grupoDe(_m(terreno: 'X', punto: 'P2', observaciones: 'control de calidad')),
        GrupoMuestreo.controles);
  });

  test('construirReportePdf produce un PDF válido no vacío', () async {
    final bytes = await construirReportePdf(
      [
        _m(terreno: 'Terreno A', punto: 'P1', humedad: 56, ce: 40, condicion: 'normal'),
        _m(terreno: 'Control', punto: 'C1', humedad: 40, ce: 250, condicion: 'moderado'),
        _m(terreno: 'Banco', punto: 'B1', humedad: 20, ce: 900, condicion: 'crítico'),
        // Sin humedad/CE: debe salir sin romper (clase/score en '—').
        _m(terreno: 'Terreno B', punto: 'P9'),
      ],
      generadoEn: DateTime(2026, 7, 11, 9, 30),
    );

    expect(bytes.length, greaterThan(1000));
    // Firma de archivo PDF: "%PDF".
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });

  test('construirReportePdf con lista vacía no lanza', () async {
    final bytes = await construirReportePdf([], generadoEn: DateTime(2026, 1, 1));
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
