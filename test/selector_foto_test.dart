// Prueba la lógica de la foto SIN dispositivo: la parte pura persistirFoto
// (copiar la imagen a almacenamiento persistente) y la interfaz mockeable
// SelectorFoto. La cámara/galería real (image_picker) no se prueba aquí; se
// aísla tras SelectorFoto para poder inyectar un doble en los tests.
//
//   flutter test test/selector_foto_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monitoreo_suelo/logica/selector_foto.dart';
import 'package:path/path.dart' as p;

/// Doble de prueba: devuelve una ruta prefijada (o null para simular cancelar).
class SelectorFotoFake implements SelectorFoto {
  SelectorFotoFake({this.rutaCamara, this.rutaGaleria});

  final String? rutaCamara;
  final String? rutaGaleria;
  OrigenFoto? ultimoOrigen;

  @override
  Future<String?> capturar(OrigenFoto origen) async {
    ultimoOrigen = origen;
    return origen == OrigenFoto.camara ? rutaCamara : rutaGaleria;
  }
}

void main() {
  group('persistirFoto', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('foto_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('copia la imagen al directorio destino y conserva el contenido',
        () async {
      final origen = File(p.join(tmp.path, 'origen.jpg'));
      await origen.writeAsBytes([1, 2, 3, 4, 5]);
      final destino = Directory(p.join(tmp.path, 'fotos'));

      final rutaFinal = await persistirFoto(origen.path, destino);

      // Queda dentro del directorio destino, con extensión conservada.
      expect(p.dirname(rutaFinal), destino.path);
      expect(p.extension(rutaFinal), '.jpg');
      // El archivo existe y su contenido es el mismo.
      final copiado = File(rutaFinal);
      expect(await copiado.exists(), isTrue);
      expect(await copiado.readAsBytes(), [1, 2, 3, 4, 5]);
      // El original sigue existiendo (se copia, no se mueve).
      expect(await origen.exists(), isTrue);
    });

    test('crea el directorio destino si no existe', () async {
      final origen = File(p.join(tmp.path, 'origen.png'));
      await origen.writeAsBytes([9, 9, 9]);
      final destino = Directory(p.join(tmp.path, 'no', 'existe', 'aun'));
      expect(await destino.exists(), isFalse);

      final rutaFinal = await persistirFoto(origen.path, destino);

      expect(await destino.exists(), isTrue);
      expect(await File(rutaFinal).exists(), isTrue);
      expect(p.extension(rutaFinal), '.png');
    });
  });

  group('SelectorFoto (interfaz mockeable)', () {
    test('capturar devuelve la ruta según el origen', () async {
      final fake = SelectorFotoFake(
        rutaCamara: '/fotos/camara.jpg',
        rutaGaleria: '/fotos/galeria.jpg',
      );
      expect(await fake.capturar(OrigenFoto.camara), '/fotos/camara.jpg');
      expect(fake.ultimoOrigen, OrigenFoto.camara);
      expect(await fake.capturar(OrigenFoto.galeria), '/fotos/galeria.jpg');
      expect(fake.ultimoOrigen, OrigenFoto.galeria);
    });

    test('capturar devuelve null cuando el usuario cancela', () async {
      final fake = SelectorFotoFake(); // sin rutas => cancela
      expect(await fake.capturar(OrigenFoto.camara), isNull);
      expect(await fake.capturar(OrigenFoto.galeria), isNull);
    });
  });
}
