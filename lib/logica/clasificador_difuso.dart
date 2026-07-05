// =====================================================================
//  MÓDULO 3 — Clasificador difuso de condición de suelo
// ---------------------------------------------------------------------
//  SISTEMA DE INFERENCIA DIFUSA DE MAMDANI. Combina HUMEDAD (%),
//  CONDUCTIVIDAD ELÉCTRICA CE (µS/cm) y TEMPERATURA (°C) en un
//  "índice de condición" CONTINUO 0–100 y lo etiqueta como
//  normal / moderado / crítico.
//
//  El motor recorre las 4 ETAPAS clásicas de Mamdani (ver clasificar()):
//    1) FUZZIFICACIÓN — cada entrada se evalúa contra FUNCIONES DE
//       PERTENENCIA trapezoidales (_mu) para obtener su grado [0..1].
//    2) EVALUACIÓN DE REGLAS — el AND de cada regla se resuelve con el
//       MÍNIMO de las pertenencias de sus antecedentes.
//    3) AGREGACIÓN — la fuerza de cada categoría de salida se combina
//       con el MÁXIMO de todas las reglas que la activan.
//    4) DEFUZZIFICACIÓN — se colapsa el conjunto de salida agregado a un
//       único score mediante el CENTROIDE sobre el universo 0..100.
//
//  IMPORTANTE PARA EL REVISOR: los condicionales al final de clasificar()
//  NO deciden la clase; SOLO ETIQUETAN el score continuo que ya calculó
//  el centroide (score >= umbral -> nombre de la categoría). Toda la
//  inferencia difusa ocurre en las etapas 1–4; el if/else es cosmético.
//
//  Es una CLASIFICACIÓN PRELIMINAR, de apoyo. No certifica el terreno.
//  pH y NPK quedan fuera (no fiables en este sensor).
// =====================================================================

// --- Funciones de pertenencia de ENTRADA (puntos a,b,c,d del trapecio;
//     triangular = b==c). ---
//
//  UMBRALES PRELIMINARES, pendientes de confirmación por criterio
//  experto. La CE se alinea a las clases de salinidad de USDA-NRCS
//  (no salino <2000, ligeramente salino 2000–4000, salino >4000 µS/cm);
//  los rangos de pH se alinearán a EN 206 cuando se incorporen a futuro.

// Conductividad eléctrica CE (µS/cm) — clases de salinidad USDA-NRCS.
const List<double> _ceBaja = [0, 0, 1500, 2500];
const List<double> _ceMedia = [2000, 3000, 3500, 4500];
const List<double> _ceAlta = [4000, 6000, 12000, 12000];

// Humedad (%) — la banda "alta" arranca en 80 % para que una humedad
// común (~70 %) no cuente como alta (el sensor tiende a sobreestimar).
const List<double> _humBaja = [0, 0, 30, 45];
const List<double> _humMedia = [35, 55, 70, 85];
const List<double> _humAlta = [80, 92, 100, 100];

// Temperatura (°C)
const List<double> _tempAlta = [35, 40, 50, 50];
// (Temp Baja/Media existen en el modelo conceptual pero solo Temp Alta
//  participa en las reglas como factor agravante; se omiten por ahora.)

// --- Funciones de pertenencia de SALIDA: índice de condición 0–100.
//     Valores preliminares, sujetos a validación por panel experto. ---
const List<double> _salNormal = [0, 0, 25, 45];
const List<double> _salModerada = [35, 50, 50, 65]; // triangular en 50
const List<double> _salCritica = [55, 75, 100, 100];

// --- Umbrales (valores preliminares, sujetos a validación) ---
const double _umbralModerado = 40; // score >= -> moderado
const double _umbralCritico = 60; // score >= -> crítico
const double _umbralVariableAlterada = 0.5; // pertenencia al extremo

/// Resultado de la clasificación difusa de una lectura.
class Clasificacion {
  /// 'normal' | 'moderado' | 'crítico'
  final String categoria;

  /// Índice de condición 0–100 (centroide de la salida difusa).
  final double score;

  /// Variables cuya pertenencia al conjunto extremo supera 0.5
  /// (CE Alta, Humedad Alta, Temp Alta). Se usan en la alerta preventiva.
  final List<String> variablesAlteradas;

  const Clasificacion({
    required this.categoria,
    required this.score,
    required this.variablesAlteradas,
  });
}

/// Pertenencia trapezoidal de [x] al conjunto definido por [p] = [a,b,c,d].
/// Soporta hombros (a==b o c==d) y triangulares (b==c).
double _mu(double x, List<double> p) {
  final a = p[0], b = p[1], c = p[2], d = p[3];
  if (x >= b && x <= c) return 1.0; // meseta
  if (x > a && x < b) return (x - a) / (b - a); // flanco ascendente
  if (x > c && x < d) return (d - x) / (d - c); // flanco descendente
  return 0.0;
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// Clasifica una lectura con un motor difuso Mamdani.
///
/// [humedad] (%) y [ce] (µS/cm) son obligatorias. [temperatura] (°C) es
/// opcional: si es null, el factor agravante por temperatura no se activa.
Clasificacion clasificar({
  required double humedad,
  required double ce,
  double? temperatura,
}) {
  // ETAPA 1 — FUZZIFICACIÓN: pertenencia de las entradas a cada conjunto.
  final ceB = _mu(ce, _ceBaja);
  final ceM = _mu(ce, _ceMedia);
  final ceA = _mu(ce, _ceAlta);
  final huB = _mu(humedad, _humBaja);
  final huM = _mu(humedad, _humMedia);
  final huA = _mu(humedad, _humAlta);
  final teA = temperatura == null ? 0.0 : _mu(temperatura, _tempAlta);

  // ETAPA 2 — EVALUACIÓN DE REGLAS: el AND de cada regla se resuelve con
  //    el MÍNIMO de sus antecedentes.
  double fNormal = 0, fModerada = 0, fCritica = 0;

  fNormal = _max(fNormal, _min(ceB, huB)); // R1  CE Baja  & Hum Baja
  fNormal = _max(fNormal, _min(ceB, huM)); // R2  CE Baja  & Hum Media
  fModerada = _max(fModerada, _min(ceB, huA)); // R3  CE Baja  & Hum Alta
  fModerada = _max(fModerada, _min(ceM, huB)); // R4  CE Media & Hum Baja
  fModerada = _max(fModerada, _min(ceM, huM)); // R5  CE Media & Hum Media
  fCritica = _max(fCritica, _min(ceM, huA)); // R6  CE Media & Hum Alta
  fCritica = _max(fCritica, _min(ceA, huB)); // R7  CE Alta  & Hum Baja
  fCritica = _max(fCritica, _min(ceA, huM)); // R8  CE Alta  & Hum Media
  fCritica = _max(fCritica, _min(ceA, huA)); // R9  CE Alta  & Hum Alta
  fCritica = _max(fCritica, _min(teA, ceM)); // R10 Temp Alta & CE Media

  // ETAPA 3 — AGREGACIÓN (por MÁXIMO) + ETAPA 4 — DEFUZZIFICACIÓN (por
  //    CENTROIDE) sobre el universo 0..100 (paso 1): en cada punto x se
  //    toma el máximo de los conjuntos de salida recortados y se calcula
  //    el centroide del resultado.
  double numerador = 0, denominador = 0;
  for (int x = 0; x <= 100; x++) {
    final xd = x.toDouble();
    final agregado = _max(
      _min(fNormal, _mu(xd, _salNormal)),
      _max(
        _min(fModerada, _mu(xd, _salModerada)),
        _min(fCritica, _mu(xd, _salCritica)),
      ),
    );
    numerador += xd * agregado;
    denominador += agregado;
  }
  final score = denominador == 0 ? 0.0 : numerador / denominador;

  // ETIQUETADO (NO es una etapa difusa): sólo se le pone nombre al score
  // continuo ya calculado por el centroide. Este if/else NO decide la
  // clase, únicamente la nombra según los umbrales.
  final categoria = score >= _umbralCritico
      ? 'crítico'
      : score >= _umbralModerado
          ? 'moderado'
          : 'normal';

  // VARIABLES ALTERADAS (para la alerta preventiva, ajena a la inferencia):
  // se marca cada entrada con pertenencia al conjunto extremo > 0.5.
  final alteradas = <String>[];
  if (ceA > _umbralVariableAlterada) alteradas.add('Conductividad (CE) alta');
  if (huA > _umbralVariableAlterada) alteradas.add('Humedad alta');
  if (teA > _umbralVariableAlterada) alteradas.add('Temperatura alta');

  return Clasificacion(
    categoria: categoria,
    score: score,
    variablesAlteradas: alteradas,
  );
}
