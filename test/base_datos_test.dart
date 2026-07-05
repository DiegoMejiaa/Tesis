// Verifica la lógica de la base de datos (Módulo 2) SIN un teléfono, usando
// sqflite_common_ffi (SQLite real corriendo en el PC).
//
//   flutter test test/base_datos_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:monitoreo_suelo/datos/base_datos.dart';
import 'package:monitoreo_suelo/modelos/medicion.dart';

Future<void> _limpiar() async {
  for (final m in await BaseDatos.instancia.obtenerTodas()) {
    await BaseDatos.instancia.borrar(m.id!);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_limpiar);

  test('insertar y leer una medición', () async {
    final id = await BaseDatos.instancia.insertar(Medicion(
      terreno: 'Terreno A',
      punto: 'P1',
      fechaHora: '2026-06-29T10:00:00',
      humedad: 68.3,
      temperatura: 24.6,
      ce: 1459,
      ph: 6.7,
      nLecturas: 5,
      observaciones: 'prueba',
      foto: '/data/fotos/foto_p1.jpg',
    ));
    expect(id, greaterThan(0));

    final todas = await BaseDatos.instancia.obtenerTodas();
    expect(todas.length, 1);
    final m = todas.first;
    expect(m.terreno, 'Terreno A');
    expect(m.punto, 'P1');
    expect(m.humedad, 68.3);
    expect(m.ce, 1459);
    expect(m.ph, 6.7); // el pH crudo se guarda y se lee de vuelta
    expect(m.nLecturas, 5);
    expect(m.observaciones, 'prueba');
    expect(m.foto, '/data/fotos/foto_p1.jpg'); // la ruta de la foto sobrevive
  });

  test('contar y borrar', () async {
    await BaseDatos.instancia
        .insertar(Medicion(terreno: 'A', punto: 'P1', fechaHora: 'x'));
    await BaseDatos.instancia
        .insertar(Medicion(terreno: 'A', punto: 'P2', fechaHora: 'y'));
    expect(await BaseDatos.instancia.contar(), 2);

    final todas = await BaseDatos.instancia.obtenerTodas();
    await BaseDatos.instancia.borrar(todas.first.id!);
    expect(await BaseDatos.instancia.contar(), 1);
  });

  test('orden: la más reciente primero (id DESC)', () async {
    await BaseDatos.instancia
        .insertar(Medicion(terreno: 'A', punto: 'P1', fechaHora: 'x'));
    await BaseDatos.instancia
        .insertar(Medicion(terreno: 'A', punto: 'P2', fechaHora: 'y'));
    final todas = await BaseDatos.instancia.obtenerTodas();
    expect(todas.first.punto, 'P2'); // última insertada → id mayor → primera
  });

  test('exportarCsv: encabezado, escape de comillas y comas', () async {
    await BaseDatos.instancia.insertar(Medicion(
      terreno: 'Terreno "Norte"', // comillas para probar el escape
      punto: 'P1',
      fechaHora: '2026-06-29T10:00:00',
      humedad: 68.3,
      temperatura: 24.6,
      ce: 1459,
      ph: 6.7,
      nLecturas: 5,
      observaciones: 'con, coma',
      foto: '/data/fotos/foto_norte.jpg',
    ));
    final csv = await BaseDatos.instancia.exportarCsv();
    final lineas = csv.trim().split('\n');

    expect(lineas.first,
        'id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,observaciones,condicion,foto');
    expect(lineas.length, 2);
    expect(csv, contains('"Terreno ""Norte"""')); // comillas duplicadas
    expect(csv, contains('"con, coma"')); // coma dentro de campo entrecomillado
    expect(csv, contains('68.3'));
    expect(csv, contains('6.7')); // el pH crudo se exporta en el CSV
    expect(csv, contains('"/data/fotos/foto_norte.jpg"')); // la ruta de la foto
  });

  test('Medicion.toMap/fromMap es ida y vuelta', () {
    final original = Medicion(
      id: 7,
      terreno: 'B',
      punto: 'P3',
      fechaHora: '2026-06-29T12:00:00',
      humedad: 50.0,
      temperatura: 22.2,
      ce: 800,
      ph: 7.1,
      nLecturas: 4,
      observaciones: 'obs',
      condicion: 'normal',
      foto: '/data/fotos/foto_p3.jpg',
    );
    final copia = Medicion.fromMap(original.toMap());
    expect(copia.id, 7);
    expect(copia.terreno, 'B');
    expect(copia.punto, 'P3');
    expect(copia.humedad, 50.0);
    expect(copia.ph, 7.1); // el pH sobrevive el ida y vuelta toMap/fromMap
    expect(copia.condicion, 'normal');
    expect(copia.foto, '/data/fotos/foto_p3.jpg'); // la foto también
  });
}
