// =====================================================================
//  Acceso a la foto por punto (cámara / galería) — Módulo "Foto"
// ---------------------------------------------------------------------
//  El acceso REAL al dispositivo (cámara/galería) vive tras la interfaz
//  SelectorFoto para poder mockearlo en tests: la captura en vivo no se
//  puede probar sin teléfono, pero la lógica de datos (persistir/guardar/
//  leer/exportar la ruta) sí. La implementación real usa image_picker y
//  copia la imagen a un directorio persistente de la app (no al caché
//  temporal que devuelve image_picker) para no perder la foto.
// =====================================================================

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// De dónde sacar la foto de un punto.
enum OrigenFoto { camara, galeria }

/// Interfaz mockeable para obtener la foto de un punto. Devuelve la ruta
/// absoluta de la imagen ya persistida, o null si el usuario canceló.
abstract class SelectorFoto {
  Future<String?> capturar(OrigenFoto origen);
}

/// Implementación real: toma/elige la imagen con image_picker y la copia al
/// almacenamiento persistente de la app. No se prueba con tests (usa canales
/// de plataforma); la parte pura y testeable es [persistirFoto].
class SelectorFotoImagePicker implements SelectorFoto {
  SelectorFotoImagePicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> capturar(OrigenFoto origen) async {
    // Con CAMERA declarado en el manifest, Android exige pedir el permiso en
    // tiempo de ejecución; image_picker no lo hace por sí solo.
    if (origen == OrigenFoto.camara) {
      final permiso = await Permission.camera.request();
      if (!permiso.isGranted) return null;
    }
    final elegida = await _picker.pickImage(
      source: origen == OrigenFoto.camara
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1600, // limita el tamaño: fotos de campo, no de estudio
      imageQuality: 85,
    );
    if (elegida == null) return null; // el usuario canceló
    final destino = await _directorioFotos();
    return persistirFoto(elegida.path, destino);
  }

  Future<Directory> _directorioFotos() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'fotos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// Copia la imagen de [rutaOrigen] a [destino] con un nombre único y devuelve
/// la nueva ruta. Función pura (solo dart:io): se puede probar sin dispositivo.
Future<String> persistirFoto(String rutaOrigen, Directory destino) async {
  if (!await destino.exists()) await destino.create(recursive: true);
  final ext = p.extension(rutaOrigen).isEmpty ? '.jpg' : p.extension(rutaOrigen);
  final nombre = 'foto_${DateTime.now().millisecondsSinceEpoch}$ext';
  final rutaDestino = p.join(destino.path, nombre);
  await File(rutaOrigen).copy(rutaDestino);
  return rutaDestino;
}
