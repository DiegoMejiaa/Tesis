// =====================================================================
//  Modelo de datos: una medición del dataset piloto
// ---------------------------------------------------------------------
//  Cada registro guarda terreno, punto, fecha/hora, las variables del
//  sensor y observaciones. "condicion" queda reservada para el Módulo 3
//  (clasificación difusa) y por ahora puede ir nula.
// =====================================================================

class Medicion {
  final int? id;
  final String terreno;
  final String punto;
  final String fechaHora; // ISO 8601 (DateTime.toIso8601String())
  final double? humedad;
  final double? temperatura;
  final double? ce;
  final double? ph; // pH crudo del sensor: se guarda para reanálisis, NO se
  // muestra en las tarjetas principales ni entra a la clasificación (Módulo 3).
  final int? nLecturas;
  final String observaciones;
  final String? condicion; // normal / moderado / crítico (Módulo 3)
  final String? foto; // ruta local de la foto del punto (opcional)
  final double? latitud; // GPS del punto (grados decimales); null si no hubo
  final double? longitud; // permiso/señal al guardar. Registros viejos: null.

  Medicion({
    this.id,
    required this.terreno,
    required this.punto,
    required this.fechaHora,
    this.humedad,
    this.temperatura,
    this.ce,
    this.ph,
    this.nLecturas,
    this.observaciones = '',
    this.condicion,
    this.foto,
    this.latitud,
    this.longitud,
  });

  /// true si tiene coordenadas válidas (se puede dibujar en el mapa).
  bool get tieneCoordenadas => latitud != null && longitud != null;

  // Convierte a Map para guardar en SQLite.
  Map<String, Object?> toMap() => {
    'id': id,
    'terreno': terreno,
    'punto': punto,
    'fecha_hora': fechaHora,
    'humedad': humedad,
    'temperatura': temperatura,
    'ce': ce,
    'ph': ph,
    'n_lecturas': nLecturas,
    'observaciones': observaciones,
    'condicion': condicion,
    'foto': foto,
    'latitud': latitud,
    'longitud': longitud,
  };

  // Reconstruye desde un Map leído de SQLite.
  factory Medicion.fromMap(Map<String, Object?> m) => Medicion(
    id: m['id'] as int?,
    terreno: (m['terreno'] as String?) ?? '',
    punto: (m['punto'] as String?) ?? '',
    fechaHora: (m['fecha_hora'] as String?) ?? '',
    humedad: (m['humedad'] as num?)?.toDouble(),
    temperatura: (m['temperatura'] as num?)?.toDouble(),
    ce: (m['ce'] as num?)?.toDouble(),
    ph: (m['ph'] as num?)?.toDouble(),
    nLecturas: (m['n_lecturas'] as num?)?.toInt(),
    observaciones: (m['observaciones'] as String?) ?? '',
    condicion: m['condicion'] as String?,
    foto: m['foto'] as String?,
    latitud: (m['latitud'] as num?)?.toDouble(),
    longitud: (m['longitud'] as num?)?.toDouble(),
  );

  // Fecha/hora legible para mostrar en pantalla.
  String get fechaLegible {
    final d = DateTime.tryParse(fechaHora);
    if (d == null) return fechaHora;
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }
}
