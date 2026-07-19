// =====================================================================
//  Configuración de la INTERPRETACIÓN DE APOYO con un LLM (Google Gemini)
// ---------------------------------------------------------------------
//  Es una capa OPCIONAL de PRESENTACIÓN: redacta en lenguaje natural una
//  lectura de la clasificación difusa. NO reemplaza ni modifica el
//  clasificador (lib/logica/clasificador_difuso.dart). Si no hay API key o
//  falla la red, la app funciona igual mostrando solo la clasificación.
//
//  CÓMO ACTIVARLA:
//    1. Entrá a  https://aistudio.google.com/apikey  (tiene plan gratis).
//    2. Generá una API key.
//    3. Pegala abajo, entre las comillas de [_apiKeyConstante], y guardá.
//
//  Alternativa sin tocar el código (útil para no subir la key al repo):
//    flutter run --dart-define=GEMINI_API_KEY=tu_key
//  Lo pasado por --dart-define tiene prioridad sobre la constante de abajo.
// =====================================================================

class ConfigLLM {
  const ConfigLLM._();

  // >>> PEGÁ TU API KEY DE GEMINI ACÁ (entre las comillas) <<<
  static const String _apiKeyConstante = '';

  /// API key efectiva: prioriza --dart-define=GEMINI_API_KEY; si no, usa la
  /// constante de arriba.
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: _apiKeyConstante,
  );

  /// Modelo de Gemini a usar (plan gratis). Cambialo acá si querés otro
  /// (por ejemplo 'gemini-2.5-flash').
  static const String modelo = 'gemini-2.0-flash';

  /// true si hay una API key configurada (por constante o por --dart-define).
  static bool get hayApiKey => apiKey.trim().isNotEmpty;
}
