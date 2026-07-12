import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/parseo_lectura.dart';

void main() {
  group('parsearLectura', () {
    test('devuelve null ante JSON malformado, incompleto o no objeto', () {
      expect(parsearLectura(''), isNull);
      expect(parsearLectura('basura'), isNull);
      expect(parsearLectura('{"punto":"P1"'), isNull);
      expect(parsearLectura('[1, 2, 3]'), isNull);
      expect(parsearLectura('null'), isNull);
    });

    test('acepta campos faltantes o null sin lanzar', () {
      final lectura = parsearLectura(
        '{"punto":"P1","humedad":null,"temperatura":24.6}',
      );

      expect(lectura, isNotNull);
      expect(lectura!.punto, 'P1');
      expect(lectura.humedad, isNull);
      expect(lectura.temperatura, 24.6);
      expect(lectura.ce, isNull);
      expect(lectura.nLecturas, isNull);
    });

    test('convierte numeros enviados como string', () {
      final lectura = parsearLectura(
        '{"punto":"P2","humedad":"68.3","temperatura":"24.6",'
        '"ph":"6.7","ce":"1459","n_lecturas":"5"}',
      );

      expect(lectura, isNotNull);
      expect(lectura!.punto, 'P2');
      expect(lectura.humedad, 68.3);
      expect(lectura.temperatura, 24.6);
      expect(lectura.ph, 6.7);
      expect(lectura.ph, isNot(lectura.humedad));
      expect(lectura.ce, 1459);
      expect(lectura.nLecturas, 5);
    });

    test('detecta estado de error reportado por la ESP32', () {
      final lectura = parsearLectura('{"estado":"error"}');

      expect(lectura, isNotNull);
      expect(lectura!.esError, isTrue);
    });

    test('voltaje: se parsea si viene, y queda null si no viene', () {
      final con = parsearLectura(
        '{"punto":"P1","humedad":56,"ce":40,"voltaje":10.4}',
      );
      expect(con, isNotNull);
      expect(con!.voltaje, 10.4);

      // Sin el campo "voltaje": queda null (el firmware puede no enviarlo).
      final sin = parsearLectura('{"punto":"P1","humedad":56,"ce":40}');
      expect(sin, isNotNull);
      expect(sin!.voltaje, isNull);
    });
  });
}
