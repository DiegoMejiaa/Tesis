// =====================================================================
//  Interpretación de apoyo con LLM (Google Gemini) — CAPA DE PRESENTACIÓN
// ---------------------------------------------------------------------
//  Sobre una medición YA CLASIFICADA por el motor difuso, pide al LLM 2-3
//  frases en lenguaje natural que interpreten el resultado. Es SOLO apoyo
//  de redacción: NO decide la clase, NO toca umbrales ni el clasificador
//  (lib/logica/clasificador_difuso.dart). La decisión la sigue tomando la
//  lógica difusa; este texto es una orientación PRELIMINAR, no un dictamen.
//
//  Diseñado para fallar en silencio: si no hay API key, no hay internet o
//  la API responde mal, se lanza [InterpretacionException] y la UI muestra
//  solo la clasificación. NUNCA debe crashear la app.
// =====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config_llm.dart';

/// Datos (YA calculados por el clasificador y la capa de corrosividad) que se
/// envían al LLM. Acá no se recalcula nada: solo se transportan para redactar.
class DatosInterpretacion {
  /// Clase de corrosividad en texto: "Baja corrosividad" / "Corrosividad
  /// moderada" / "Alta corrosividad" (ver logica/corrosividad.dart).
  final String clase;

  /// Índice de condición 0-100 del centroide difuso, redondeado.
  final int score;

  final double? ce; // µS/cm
  final double? resistividad; // Ω·cm equivalente (1e6 / CE)
  final double? humedad; // %
  final double? temperatura; // °C
  final double? ph;

  /// Variables cuya pertenencia al extremo superó 0.5 (si las hay).
  final List<String> variablesAltas;

  const DatosInterpretacion({
    required this.clase,
    required this.score,
    this.ce,
    this.resistividad,
    this.humedad,
    this.temperatura,
    this.ph,
    this.variablesAltas = const [],
  });
}

/// Capa que redacta la interpretación de apoyo. Abstracta para poder
/// inyectar un mock en tests / previsualización.
abstract class InterpretadorLLM {
  /// true si se puede intentar generar texto (p. ej. hay API key configurada).
  bool get disponible;

  /// Devuelve 2-3 frases interpretando [d]. Lanza [InterpretacionException]
  /// si no hay conexión, no hay key o la API falla.
  Future<String> interpretar(DatosInterpretacion d);
}

/// Falla de la capa de interpretación (red caída, API sin respuesta, etc.).
/// Es esperable y NO debe propagarse como crash: la UI la captura.
class InterpretacionException implements Exception {
  final String mensaje;
  const InterpretacionException(this.mensaje);
  @override
  String toString() => 'InterpretacionException: $mensaje';
}

/// Implementación real contra la API de Google Gemini (generativelanguage).
class InterpretadorGemini implements InterpretadorLLM {
  InterpretadorGemini({http.Client? cliente, String? apiKey, String? modelo})
    : _cliente = cliente ?? http.Client(),
      _apiKey = apiKey ?? ConfigLLM.apiKey,
      _modelo = modelo ?? ConfigLLM.modelo;

  final http.Client _cliente;
  final String _apiKey;
  final String _modelo;

  static const Duration _timeout = Duration(seconds: 20);

  @override
  bool get disponible => _apiKey.trim().isNotEmpty;

  @override
  Future<String> interpretar(DatosInterpretacion d) async {
    if (!disponible) {
      throw const InterpretacionException('Sin API key configurada.');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_modelo:generateContent',
    );
    final cuerpo = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': construirPromptInterpretacion(d)},
          ],
        },
      ],
      // Tono sobrio y respuesta corta (el prompt pide máximo 60 palabras).
      // Sin thinkingConfig: gemini-flash-lite-latest no gasta tokens en
      // "pensamiento", así que toda la respuesta sale completa y sin cortes.
      'generationConfig': {
        'temperature': 0.4,
        'topP': 0.9,
        'maxOutputTokens': 400,
      },
    });

    http.Response resp;
    try {
      resp = await _cliente
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: cuerpo,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const InterpretacionException('Tiempo de espera agotado.');
    } catch (e) {
      // SocketException (sin internet), HandshakeException, etc.
      throw InterpretacionException('Sin conexión ($e).');
    }

    if (resp.statusCode != 200) {
      throw InterpretacionException('La API respondió ${resp.statusCode}.');
    }

    final texto = extraerTextoGemini(resp.body);
    if (texto == null || texto.trim().isEmpty) {
      throw const InterpretacionException('Respuesta vacía del modelo.');
    }
    return texto.trim();
  }

  /// Libera el cliente HTTP subyacente.
  void cerrar() => _cliente.close();
}

/// Construye el prompt RESTRINGIDO en español para el LLM. Público para poder
/// probarlo sin red. El LLM solo redacta: no puede certificar ni recomendar
/// medidas de protección (ver prohibiciones al final del prompt).
String construirPromptInterpretacion(DatosInterpretacion d) {
  String num1(double? v) => v == null ? '—' : v.toStringAsFixed(1);
  String ent(double? v) => v == null ? '—' : v.round().toString();
  final resistTxt = (d.resistividad != null && d.resistividad!.isInfinite)
      ? 'muy alta'
      : ent(d.resistividad);

  final buffer = StringBuffer()
    ..write(
      'Sos un asistente que INFORMA, en lenguaje natural, una clasificación '
      'PRELIMINAR de corrosividad del suelo para obra civil. La herramienta '
      'informa y DEFIERE al criterio profesional: no decide, no prescribe. '
      'Datos: ${d.clase}, score ${d.score}/100, conductividad ${ent(d.ce)} '
      'µS/cm, resistividad equivalente $resistTxt Ω·cm, humedad '
      '${num1(d.humedad)} %, pH ${num1(d.ph)}, temperatura '
      '${num1(d.temperatura)} °C. ',
    );
  if (d.variablesAltas.isNotEmpty) {
    buffer.write('Variables elevadas: ${d.variablesAltas.join(', ')}. ');
  }
  buffer.write(
    'Redactá 2-3 frases que: (a) informen el nivel preliminar de corrosividad, '
    '(b) indiquen que la conductividad es la variable determinante, y (c) '
    'cierren con que la valoración final corresponde al criterio profesional. '
    'Guía según el nivel: para "Baja corrosividad", que no se evidencian '
    'indicadores de corrosividad relevantes; para "Corrosividad moderada", que '
    'sugiere una corrosividad intermedia determinada por la conductividad; para '
    '"Alta corrosividad", que sugiere una corrosividad elevada determinada por '
    'la conductividad. '
    'REGLAS ESTRICTAS: PROHIBIDO prescribir estudios o acciones específicas, '
    'certificar el terreno, decir si necesita o no protección, y usar verbos '
    'imperativos ("realice", "necesita", "debe"). Solo INFORMÁ el nivel '
    'preliminar y aclará que la valoración final es del profesional. Indicá '
    'SIEMPRE que es una orientación preliminar de apoyo. Máximo 55 palabras, '
    'tono técnico y sobrio.',
  );
  return buffer.toString();
}

/// Extrae el texto de la respuesta JSON de Gemini. Devuelve null si el cuerpo
/// no tiene el formato esperado (nunca lanza). Público para poder probarlo.
String? extraerTextoGemini(String body) {
  try {
    final decodificado = jsonDecode(body);
    if (decodificado is! Map) return null;
    final candidates = decodificado['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final primero = candidates.first;
    if (primero is! Map) return null;
    final content = primero['content'];
    if (content is! Map) return null;
    final parts = content['parts'];
    if (parts is! List) return null;
    final buffer = StringBuffer();
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['thought'] == true) continue; // ignora partes de "pensamiento"
      if (p['text'] is String) buffer.write(p['text']);
    }
    final s = buffer.toString().trim();
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}
