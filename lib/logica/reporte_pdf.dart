// =====================================================================
//  Reporte PDF de corrosividad de suelos (obras civiles) — Módulo 5
// ---------------------------------------------------------------------
//  Construye un PDF con: (1) un resumen general, y (2) una tabla de
//  puntos por grupo de muestreo (Campo / Controles / Banco) con
//  terreno, punto, humedad, CE, resistividad, pH, clase y score.
//
//  Es SOLO presentación/exportación: usa el clasificador difuso actual
//  (lib/logica/clasificador_difuso.dart) en modo lectura y NO lo modifica.
//  El PDF se arma con el paquete `pdf` (Dart puro), así que puede probarse
//  sin dispositivo. El compartir/guardar lo hace la pantalla con `printing`.
// =====================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'clasificador_difuso.dart';
import 'corrosividad.dart';
import '../modelos/medicion.dart';

/// Grupo de muestreo inferido del texto del terreno/punto/observaciones.
enum GrupoMuestreo { campo, controles, banco }

String nombreGrupo(GrupoMuestreo g) => switch (g) {
      GrupoMuestreo.campo => 'Campo',
      GrupoMuestreo.controles => 'Controles',
      GrupoMuestreo.banco => 'Banco',
    };

/// Clasifica una medición en un grupo de muestreo por palabras clave. Si no hay
/// pista en el texto, se asume "Campo".
GrupoMuestreo grupoDe(Medicion m) {
  final t = '${m.terreno} ${m.punto} ${m.observaciones}'.toLowerCase();
  if (t.contains('control')) return GrupoMuestreo.controles;
  if (t.contains('banco')) return GrupoMuestreo.banco;
  return GrupoMuestreo.campo;
}

/// Construye el PDF del reporte y devuelve sus bytes (listos para compartir o
/// guardar). [generadoEn] permite fijar la fecha en tests.
Future<Uint8List> construirReportePdf(
  List<Medicion> mediciones, {
  DateTime? generadoEn,
}) async {
  final doc = pw.Document();
  final ahora = generadoEn ?? DateTime.now();

  // Agrupa por grupo de muestreo conservando el orden de entrada.
  final grupos = <GrupoMuestreo, List<Medicion>>{};
  for (final m in mediciones) {
    grupos.putIfAbsent(grupoDe(m), () => <Medicion>[]).add(m);
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        _encabezado(ahora),
        pw.SizedBox(height: 14),
        _resumen(mediciones),
        pw.SizedBox(height: 18),
        for (final g in GrupoMuestreo.values)
          if ((grupos[g] ?? const <Medicion>[]).isNotEmpty) ...[
            _tituloGrupo(nombreGrupo(g), grupos[g]!.length),
            pw.SizedBox(height: 6),
            _tabla(grupos[g]!),
            pw.SizedBox(height: 16),
          ],
        _interpretaciones(mediciones),
        pw.SizedBox(height: 8),
        _pie(),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _encabezado(DateTime ahora) {
  String dos(int n) => n.toString().padLeft(2, '0');
  final fecha =
      '${dos(ahora.day)}/${dos(ahora.month)}/${ahora.year} ${dos(ahora.hour)}:${dos(ahora.minute)}';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Evaluación de corrosividad de suelos para obras civiles',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Reporte de puntos de medición · Generado el $fecha',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      pw.Divider(color: PdfColors.grey400),
    ],
  );
}

pw.Widget _resumen(List<Medicion> ms) {
  var baja = 0, moderada = 0, alta = 0, sin = 0;
  for (final m in ms) {
    switch (_categoria(m)) {
      case 'normal':
        baja++;
      case 'moderado':
        moderada++;
      case 'crítico':
      case 'critico':
        alta++;
      default:
        sin++;
    }
  }

  pw.Widget item(String etiqueta, String valor) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(valor,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(etiqueta,
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Resumen',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Row(
        children: [
          item('Puntos totales', '${ms.length}'),
          pw.SizedBox(width: 10),
          item('Baja corrosividad', '$baja'),
          pw.SizedBox(width: 10),
          item('Corrosividad moderada', '$moderada'),
          pw.SizedBox(width: 10),
          item('Alta corrosividad', '$alta'),
          if (sin > 0) ...[
            pw.SizedBox(width: 10),
            item('Sin clasificar', '$sin'),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _tituloGrupo(String nombre, int n) => pw.Text(
      '$nombre  ·  $n ${n == 1 ? "punto" : "puntos"}',
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    );

pw.Widget _tabla(List<Medicion> ms) {
  final headers = [
    'Terreno',
    'Punto',
    'Humedad (%)',
    'CE (µS/cm)',
    'Resistividad (Ω·cm)',
    'pH',
    'Clase de corrosividad',
    'Score',
  ];
  final data = [for (final m in ms) _fila(m)];

  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellHeight: 20,
    cellAlignments: {
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
      5: pw.Alignment.centerRight,
      7: pw.Alignment.centerRight,
    },
  );
}

List<String> _fila(Medicion m) {
  final clas = (m.humedad != null && m.ce != null)
      ? clasificar(humedad: m.humedad!, ce: m.ce!, temperatura: m.temperatura)
      : null;
  String num(double? v, [int d = 1]) => v == null ? '—' : v.toStringAsFixed(d);
  return [
    m.terreno,
    m.punto,
    num(m.humedad),
    num(m.ce, 0),
    resistividadTexto(m.ce, conUnidad: false),
    num(m.ph, 1),
    nombreCorrosividad(_categoria(m)),
    clas == null ? '—' : '${clas.score.round()}/100',
  ];
}

// Categoría a usar para clase/resumen: prioriza la guardada; si no hay, la
// recalcula con el clasificador actual (cuando hay humedad y CE).
String? _categoria(Medicion m) {
  if (m.condicion != null && m.condicion!.isNotEmpty) return m.condicion;
  if (m.humedad != null && m.ce != null) {
    return clasificar(humedad: m.humedad!, ce: m.ce!, temperatura: m.temperatura)
        .categoria;
  }
  return null;
}

// Sección con las interpretaciones de apoyo GUARDADAS (las que tengan texto).
// Es solo presentación del texto persistido; si ninguna medición tiene
// interpretación, la sección no aparece.
pw.Widget _interpretaciones(List<Medicion> ms) {
  final conTexto = [
    for (final m in ms)
      if (m.interpretacion != null && m.interpretacion!.trim().isNotEmpty) m,
  ];
  if (conTexto.isEmpty) return pw.SizedBox();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Interpretación de apoyo (orientación preliminar)',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Texto generado por IA como apoyo; no sustituye un estudio '
        'especializado ni el criterio profesional.',
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
      pw.SizedBox(height: 8),
      for (final m in conTexto) ...[
        pw.Text(
          '${m.terreno} · Punto ${m.punto}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(m.interpretacion!.trim(),
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
      ],
    ],
  );
}

pw.Widget _pie() => pw.Text(
      'Clasificación preliminar de corrosividad (screening basado en '
      'resistividad equivalente, NACE SP0169 / AWWA C105). No certifica el '
      'terreno; requiere ensayo estandarizado (ASTM G57) para dictamen.',
      style: pw.TextStyle(
        fontSize: 8,
        color: PdfColors.grey700,
        fontStyle: pw.FontStyle.italic,
      ),
    );
