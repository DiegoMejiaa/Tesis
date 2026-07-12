// =====================================================================
//  Presentación orientada a OBRAS CIVILES (corrosividad de suelos)
// ---------------------------------------------------------------------
//  Traduce la categoría del clasificador difuso (normal/moderado/crítico)
//  al lenguaje de corrosividad usado en ingeniería civil y calcula la
//  RESISTIVIDAD equivalente del suelo. Es SOLO presentación: NO cambia el
//  cálculo ni los umbrales del clasificador (lib/logica/clasificador_difuso.dart).
//
//  Relación física (NACE SP0169 / AWWA C105):
//        resistividad(Ω·cm) = 1 000 000 / CE(µS/cm)
// =====================================================================

/// Nombre de la clase de corrosividad para una categoría del clasificador.
///   normal   -> "Baja corrosividad"
///   moderado -> "Corrosividad moderada"
///   crítico  -> "Alta corrosividad"
String nombreCorrosividad(String? categoria) {
  switch (categoria) {
    case 'crítico':
    case 'critico':
      return 'Alta corrosividad';
    case 'moderado':
      return 'Corrosividad moderada';
    case 'normal':
      return 'Baja corrosividad';
    default:
      return 'Sin clasificar';
  }
}

/// Resistividad equivalente del suelo en Ω·cm a partir de la CE (µS/cm).
///   - CE null  -> null (no se puede calcular)
///   - CE == 0  -> infinito (suelo idealmente no conductor)
///   - CE > 0   -> 1 000 000 / CE
double? resistividadOhmCm(double? ce) {
  if (ce == null) return null;
  if (ce == 0) return double.infinity;
  return 1000000 / ce;
}

/// Texto listo para mostrar de la resistividad equivalente:
///   - "—" si no hay CE
///   - "∞" si CE == 0
///   - "25 000 Ω·cm" (con separador de miles) en el caso general
String resistividadTexto(double? ce, {bool conUnidad = true}) {
  final r = resistividadOhmCm(ce);
  if (r == null) return '—';
  if (r.isInfinite) return conUnidad ? '∞ Ω·cm' : '∞';
  final n = _milesConEspacio(r.round());
  return conUnidad ? '$n Ω·cm' : n;
}

/// Formatea un entero con espacio como separador de miles: 25000 -> "25 000".
String _milesConEspacio(int n) {
  final negativo = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' '); // espacio fino
    b.write(s[i]);
  }
  return negativo ? '-$b' : b.toString();
}
