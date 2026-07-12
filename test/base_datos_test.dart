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

  test('orden: la más reciente primero (fecha_hora DESC, no por id)', () async {
    // Se inserta PRIMERO la más reciente (id menor) y luego la más antigua
    // (id mayor). Así el orden por fecha_hora es OPUESTO al de id: si ordenara
    // por id/rowid, la primera sería 'P_antigua' y el test fallaría.
    await BaseDatos.instancia.insertar(Medicion(
        terreno: 'A', punto: 'P_reciente', fechaHora: '2026-07-10T09:00:00'));
    await BaseDatos.instancia.insertar(Medicion(
        terreno: 'A', punto: 'P_antigua', fechaHora: '2026-07-01T09:00:00'));
    final todas = await BaseDatos.instancia.obtenerTodas();
    expect(todas.first.punto, 'P_reciente'); // fecha mayor → primera
    expect(todas.last.punto, 'P_antigua'); // fecha menor → última
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
        'id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,observaciones,condicion,foto,latitud,longitud');
    expect(lineas.length, 2);
    expect(csv, contains('"Terreno ""Norte"""')); // comillas duplicadas
    expect(csv, contains('"con, coma"')); // coma dentro de campo entrecomillado
    expect(csv, contains('68.3'));
    expect(csv, contains('6.7')); // el pH crudo se exporta en el CSV
    expect(csv, contains('"/data/fotos/foto_norte.jpg"')); // la ruta de la foto
  });

  test('importarCsv: reclasifica, deduplica y maneja campos vacíos', () async {
    // La columna "condicion" del CSV está a propósito EQUIVOCADA para verificar
    // que se recalcula con el clasificador actual. ph vacío en la 2da fila.
    const csv =
        'id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,observaciones,condicion,foto\n'
        '1,Terreno A,P1,2026-06-29T10:00:00,56,23.8,740,6.8,5,"obs, con coma",normal,\n'
        '2,Terreno B,P2,2026-06-29T11:00:00,40,22.0,40,,5,sin ph,critico,\n';

    final n = await BaseDatos.instancia.importarCsv(csv);
    expect(n, 2);

    final todas = await BaseDatos.instancia.obtenerTodas();
    expect(todas.length, 2);

    // ce=740 con la escala de corrosividad => crítico (el CSV decía "normal").
    final p1 = todas.firstWhere((m) => m.punto == 'P1');
    expect(p1.condicion, 'crítico');
    expect(p1.ph, 6.8);
    expect(p1.foto, ''); // foto vacía -> cadena vacía
    expect(p1.observaciones, 'obs, con coma'); // coma dentro de comillas

    // ce=40 => normal (el CSV decía "critico"); ph vacío -> null.
    final p2 = todas.firstWhere((m) => m.punto == 'P2');
    expect(p2.condicion, 'normal');
    expect(p2.ph, isNull);

    // Reimportar el MISMO csv no duplica (dedup por fecha_hora).
    final n2 = await BaseDatos.instancia.importarCsv(csv);
    expect(n2, 0);
    expect((await BaseDatos.instancia.obtenerTodas()).length, 2);
  });

  test('CSV: latitud/longitud ida y vuelta y compatibilidad con CSV viejo',
      () async {
    // Inserta con coordenadas, exporta y reimporta: las coordenadas sobreviven.
    await BaseDatos.instancia.insertar(Medicion(
      terreno: 'Terreno A',
      punto: 'P1',
      fechaHora: '2026-06-29T10:00:00',
      humedad: 56,
      ce: 40,
      latitud: 14.0870,
      longitud: -87.1650,
    ));
    final csv = await BaseDatos.instancia.exportarCsv();
    expect(csv, contains('14.087'));
    expect(csv, contains('-87.165'));

    await _limpiar();
    await BaseDatos.instancia.importarCsv(csv);
    final reimportada = (await BaseDatos.instancia.obtenerTodas()).single;
    expect(reimportada.latitud, closeTo(14.0870, 1e-9));
    expect(reimportada.longitud, closeTo(-87.1650, 1e-9));

    // Un CSV viejo (12 columnas, sin latitud/longitud) sigue importando; las
    // coordenadas quedan null y no rompe.
    await _limpiar();
    const csvViejo =
        'id,terreno,punto,fecha_hora,humedad,temperatura,ce,ph,n_lecturas,observaciones,condicion,foto\n'
        '1,Terreno B,P9,2026-05-01T08:00:00,50,22,40,,5,sin coords,,\n';
    final n = await BaseDatos.instancia.importarCsv(csvViejo);
    expect(n, 1);
    final vieja = (await BaseDatos.instancia.obtenerTodas()).single;
    expect(vieja.latitud, isNull);
    expect(vieja.longitud, isNull);
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
