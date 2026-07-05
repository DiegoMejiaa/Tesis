// =====================================================================
//  Acceso a la base de datos local (SQLite) — Módulo 2
// ---------------------------------------------------------------------
//  Guarda y consulta el historial de mediciones (dataset piloto).
//  Patrón singleton: una sola instancia para toda la app.
// =====================================================================

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
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
  Future<List<Medicion>> obtenerTodas() async {
    final db = await _baseDatos;
    final filas = await db.query('mediciones', orderBy: 'id DESC');
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
