// =====================================================================
//  Parseo tolerante del JSON que envía la ESP32 (Módulo 1)
// ---------------------------------------------------------------------
//  La ESP32 manda una línea JSON por medición:
//    {"punto","humedad","temperatura","ph","ce","n_lecturas"}
//  Este parser NUNCA lanza: ante JSON malformado, incompleto o campos
//  faltantes/null devuelve null (línea ignorable) o una lectura con los
//  campos que sí llegaron. Se aísla acá para poder probarlo sin Bluetooth.
// =====================================================================

import 'dart:convert';

class LecturaEnVivo {
  final String? punto;
  final double? humedad;
  final double? temperatura;
  final double? ce;
  final double? ph; // pH crudo (no se muestra ni clasifica; se guarda igual)
  final int? nLecturas;
  final double? voltaje; // voltaje de alimentación del sensor (V), si lo reporta
  final bool esError; // la ESP32 reportó {"estado":"error"}

  const LecturaEnVivo({
    this.punto,
    this.humedad,
    this.temperatura,
    this.ce,
    this.ph,
    this.nLecturas,
    this.voltaje,
    this.esError = false,
  });

  // Hay al menos una variable numérica utilizable.
  bool get tieneDatos =>
      humedad != null || temperatura != null || ce != null || ph != null;
}

// Parsea una línea cruda recibida por Bluetooth.
//   - Devuelve null si no es un objeto JSON de medición (texto suelto, JSON
//     incompleto/malformado, o un valor que no es objeto).
//   - Devuelve LecturaEnVivo(esError: true) si la ESP32 reporta error.
//   - Si algún campo falta o viene null, ese campo queda en null (no crashea).
LecturaEnVivo? parsearLectura(String linea) {
  final t = linea.trim();
  if (!t.startsWith('{')) return null; // ignora CSV / texto suelto
  Object? decodificado;
  try {
    decodificado = json.decode(t);
  } catch (_) {
    return null; // JSON incompleto o malformado: se espera la próxima línea
  }
  if (decodificado is! Map) return null;
  final m = decodificado;

  if (m['estado'] == 'error') return const LecturaEnVivo(esError: true);

  return LecturaEnVivo(
    punto: m['punto']?.toString(),
    humedad: _aDouble(m['humedad']),
    temperatura: _aDouble(m['temperatura']),
    ce: _aDouble(m['ce']),
    ph: _aDouble(m['ph']),
    nLecturas: _aInt(m['n_lecturas']),
    // Aditivo: si el firmware aún no envía "voltaje", queda null y no se muestra.
    voltaje: _aDouble(m['voltaje']),
  );
}

double? _aDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _aInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
