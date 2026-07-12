// =====================================================================
//  Servicio de ubicación (GPS por punto) — Módulo 1
// ---------------------------------------------------------------------
//  Captura la coordenada del punto al guardar una medición. Se aísla
//  detrás de una interfaz (igual que SelectorFoto) para poder mockearlo
//  en tests y para que la app NUNCA crashee si el permiso se niega, el
//  GPS está apagado o hay timeout: en esos casos devuelve null y la
//  medición se guarda igual, sin coordenadas.
// =====================================================================

import 'package:geolocator/geolocator.dart';

/// Coordenada geográfica en grados decimales.
class Coordenada {
  final double latitud;
  final double longitud;
  const Coordenada(this.latitud, this.longitud);
}

/// Interfaz del servicio de ubicación (inyectable / mockeable).
abstract class ServicioUbicacion {
  /// Devuelve la coordenada actual, o null si no se pudo obtener (permiso
  /// denegado, GPS apagado, timeout…). NUNCA lanza.
  Future<Coordenada?> obtener();
}

/// Implementación real sobre geolocator. Solicita el permiso en tiempo de
/// ejecución; si el usuario lo niega, devuelve null (no bloquea el guardado).
class ServicioUbicacionGeolocator implements ServicioUbicacion {
  const ServicioUbicacionGeolocator();

  @override
  Future<Coordenada?> obtener() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null; // el usuario negó el permiso: se guarda sin coordenadas
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return Coordenada(pos.latitude, pos.longitude);
    } catch (_) {
      // GPS apagado, timeout, servicio no disponible: guardar sin coordenadas.
      return null;
    }
  }
}
