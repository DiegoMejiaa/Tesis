// =====================================================================
//  Contador de mediciones guardadas por punto/terreno
// ---------------------------------------------------------------------
//  Contador REAL de cuántas mediciones se han guardado en el punto y
//  terreno actuales. OJO: es distinto de n_lecturas del firmware, que es
//  el "promedio de muestras" (siempre 5) que la ESP32 promedia por lectura.
//  Aquí, en cambio, cada medición guardada suma +1 y el conteo se reinicia
//  al cambiar de punto o de terreno.
// =====================================================================

class ContadorGuardadas {
  String? _terreno;
  String? _punto;
  int _cuenta = 0;

  /// Mediciones guardadas en el punto/terreno actual (0 si aún ninguna).
  int get cuenta => _cuenta;

  /// Registra una medición guardada en (terreno, punto) y devuelve el nuevo
  /// total para ese punto. Si cambió el terreno o el punto respecto de la
  /// última medición, reinicia el conteo en 1 (esta es la primera del punto).
  int registrar(String terreno, String punto) {
    if (terreno != _terreno || punto != _punto) {
      _terreno = terreno;
      _punto = punto;
      _cuenta = 1;
    } else {
      _cuenta += 1;
    }
    return _cuenta;
  }

  /// Reinicia el contador por completo (p. ej. al empezar de cero).
  void reiniciar() {
    _terreno = null;
    _punto = null;
    _cuenta = 0;
  }
}
