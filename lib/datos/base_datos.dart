// =====================================================================
//  Acceso a la base de datos local (SQLite) — Módulo 2
// ---------------------------------------------------------------------
//  Guarda y consulta el historial de mediciones (dataset piloto).
//  Patrón singleton: una sola instancia para toda la app.
// =====================================================================

import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../logica/clasificador_difuso.dart';
import '../modelos/medicion.dart';

class BaseDatos {
  BaseDatos._privado();
  static final BaseDatos instancia = BaseDatos._privado();

  static Database? _db;

  Future<Database> get _baseDatos async {
    _db ??= await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final dir = await getDatabasesPath();
    final ruta = p.join(dir, 'monitoreo_suelo.db');
    return openDatabase(
      ruta,
      // v2: columna `ph` (pH crudo del sensor).
      // v3: columna `foto` (ruta local de la foto del punto, opcional).
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE mediciones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            terreno TEXT NOT NULL,
            punto TEXT NOT NULL,
            fecha_hora TEXT NOT NULL,
            humedad REAL,
            temperatura REAL,
            ce REAL,
            ph REAL,
            n_lecturas INTEGER,
            observaciones TEXT,
            condicion TEXT,
            foto TEXT
          )
        ''');
      },
      onUpgrade: (db, desde, hasta) async {
        // Migraciones incrementales y seguras (ALTER TABLE), sin perder los
        // registros ya guardados en campo. Las columnas nuevas quedan NULL.
        if (desde < 2) {
          await db.execute('ALTER TABLE mediciones ADD COLUMN ph REAL');
        }
        if (desde < 3) {
          await db.execute('ALTER TABLE mediciones ADD COLUMN foto TEXT');
        }
      },
    );
  }

  // Inserta una medición y devuelve su id.
  Future<int> insertar(Medicion m) async {
    final db = await _baseDatos;
    return db.insert('mediciones', m.toMap());
  }

  // Devuelve todas las mediciones, de la más reciente a la más antigua.
  // Ordena por fecha_hora (las cadenas ISO 8601 ordenan cronológicamente), no
  // por id/rowid: así el historial refleja la fecha real de la medición aunque
  // se hayan importado o insertado en otro orden.
  Future<List<Medicion>> obtenerTodas() async {
    final db = await _baseDatos;
    final filas = await db.query('mediciones', orderBy: 'fecha_hora DESC');
    return filas.map(Medicion.fromMap).toList();
  }

  // Borra una medición por id.
  Future<void> borrar(int id) async {
    final db = await _baseDatos;
    await db.delete('mediciones', where: 'id = ?', whereArgs: [id]);
  }

  // Cuenta cuántas mediciones hay guardadas.
  Future<int> contar() async {
    final db = await _baseDatos;
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM mediciones');
    return (r.first['n'] as int?) ?? 0;
  }

  // Importa mediciones desde el CONTENIDO de un CSV con la cabecera exacta:
  //   id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,
  //   observaciones,condicion,foto
  //
  // Reglas (restaurar el historial perdido tras una reinstalación):
  //  - RECLASIFICA la condición con el clasificador difuso ACTUAL a partir de
  //    humedad/ce/temperatura; IGNORA la columna "condicion" del CSV (pudo
  //    calcularse con umbrales viejos). Así el historial queda en la escala nueva.
  //  - Campos opcionales vacíos no fallan: ph vacío -> null; foto vacío -> ''.
  //  - EVITA DUPLICADOS por fecha_hora: si ya hay una medición con esa misma
  //    marca de tiempo (en la base o repetida en el archivo) no se reinserta,
  //    así se puede reimportar sin duplicar.
  //
  // Devuelve cuántas mediciones se insertaron efectivamente.
  Future<int> importarCsv(String contenido) async {
    // Normaliza saltos de línea y quita el BOM que suele anteponer Excel.
    final texto = contenido
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final filas = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false, // controlamos el parseo (vacío -> null)
    ).convert(texto);
    if (filas.isEmpty) return 0;

    // Saltea la fila de cabecera si está presente (primera celda == "id").
    var inicio = 0;
    if (filas.first.isNotEmpty &&
        filas.first.first.toString().trim().toLowerCase() == 'id') {
      inicio = 1;
    }

    final db = await _baseDatos;

    // Conjunto de fecha_hora ya presentes (para deduplicar en una sola consulta).
    final existentes = <String>{
      for (final r in await db.query('mediciones', columns: ['fecha_hora']))
        (r['fecha_hora'] as String?) ?? '',
    };

    var insertadas = 0;
    for (var i = inicio; i < filas.length; i++) {
      final f = filas[i];
      String col(int idx) => idx < f.length ? f[idx].toString().trim() : '';
      double? real(int idx) {
        final s = col(idx);
        return s.isEmpty ? null : double.tryParse(s);
      }

      int? entero(int idx) {
        final s = col(idx);
        return s.isEmpty ? null : int.tryParse(s);
      }

      // 0 id · 1 terreno · 2 punto · 3 fecha_hora · 4 humedad · 5 temperatura ·
      // 6 ce · 7 ph · 8 n_lecturas · 9 observaciones · 10 condicion · 11 foto
      final fechaHora = col(3);
      // Fila sin marca de tiempo, cabecera colada o duplicado -> se ignora.
      if (fechaHora.isEmpty ||
          fechaHora.toLowerCase() == 'fecha_hora' ||
          existentes.contains(fechaHora)) {
        continue;
      }
      existentes.add(fechaHora);

      final humedad = real(4);
      final temperatura = real(5);
      final ce = real(6);

      // Reclasifica con la escala ACTUAL (ignora la columna "condicion" del CSV).
      final condicion = (humedad != null && ce != null)
          ? clasificar(
              humedad: humedad,
              ce: ce,
              temperatura: temperatura,
            ).categoria
          : null;

      await db.insert(
        'mediciones',
        Medicion(
          terreno: col(1),
          punto: col(2),
          fechaHora: fechaHora,
          humedad: humedad,
          temperatura: temperatura,
          ce: ce,
          ph: real(7), // vacío -> null
          nLecturas: entero(8),
          observaciones: col(9),
          condicion: condicion,
          foto: col(11), // vacío -> '' (las fotos se perdieron)
        ).toMap(),
      );
      insertadas++;
    }
    return insertadas;
  }

  // Genera el contenido CSV de todo el historial (para exportar el dataset).
  Future<String> exportarCsv() async {
    final lista = await obtenerTodas();
    final buffer = StringBuffer();
    buffer.writeln(
      'id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,observaciones,condicion,foto',
    );
    for (final m in lista) {
      String c(Object? v) {
        final s = (v ?? '').toString().replaceAll('"', '""');
        return '"$s"';
      }

      buffer.writeln(
        [
          m.id,
          c(m.terreno),
          c(m.punto),
          c(m.fechaHora),
          m.humedad ?? '',
          m.temperatura ?? '',
          m.ce ?? '',
          m.ph ?? '',
          m.nLecturas ?? '',
          c(m.observaciones),
          c(m.condicion ?? ''),
          c(m.foto ?? ''),
        ].join(','),
      );
    }
    return buffer.toString();
  }
}
