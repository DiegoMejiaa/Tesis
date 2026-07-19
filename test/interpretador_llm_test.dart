// Pruebas de la CAPA DE APOYO con LLM (Gemini). Lógica de red aislada: se
// prueba con un cliente HTTP simulado (MockClient), sin salir a internet.
//
//   flutter test test/interpretador_llm_test.dart
//
// Verifica: (1) el prompt lleva los datos y las restricciones, (2) el parseo
// tolerante de la respuesta, (3) el flujo feliz y (4) que un fallo de red se
// traduce en InterpretacionException (la UI la captura y no crashea).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monitoreo_suelo/logica/interpretador_llm.dart';

const _datos = DatosInterpretacion(
  clase: 'Alta corrosividad',
  score: 78,
  ce: 500,
  resistividad: 2000,
  humedad: 45,
  temperatura: 24,
  ph: 6.8,
  variablesAltas: ['Conductividad (CE) alta'],
);

String _respuestaGemini(String texto) => jsonEncode({
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': texto},
        ],
      },
    },
  ],
});

void main() {
  group('construirPromptInterpretacion', () {
    test('incluye los datos de la medición', () {
      final p = construirPromptInterpretacion(_datos);
      expect(p, contains('Alta corrosividad'));
      expect(p, contains('score 78/100'));
      expect(p, contains('500 µS/cm'));
      expect(p, contains('2000 Ω·cm'));
      expect(p, contains('Conductividad (CE) alta')); // variable elevada
    });

    test('impone las restricciones (orientación preliminar, no certificar)', () {
      final p = construirPromptInterpretacion(_datos);
      expect(p, contains('PROHIBIDO'));
      expect(p, contains('imperativos')); // no verbos imperativos
      expect(p, contains('criterio profesional')); // defiere al profesional
      expect(p, contains('orientación preliminar'));
      expect(p, contains('Máximo 55 palabras'));
    });

    test('tolera valores nulos sin romper', () {
      const d = DatosInterpretacion(clase: 'Baja corrosividad', score: 12);
      final p = construirPromptInterpretacion(d);
      expect(p, contains('Baja corrosividad'));
      expect(p, contains('—')); // marcador de dato ausente
    });
  });

  group('extraerTextoGemini', () {
    test('extrae el texto de una respuesta válida', () {
      final t = extraerTextoGemini(_respuestaGemini('Suelo altamente corrosivo.'));
      expect(t, 'Suelo altamente corrosivo.');
    });

    test('devuelve null ante JSON inesperado o vacío (no lanza)', () {
      expect(extraerTextoGemini('no es json'), isNull);
      expect(extraerTextoGemini('{}'), isNull);
      expect(extraerTextoGemini('{"candidates":[]}'), isNull);
    });

    test('ignora las partes de "pensamiento" (thought) del modelo', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'razonamiento interno', 'thought': true},
                {'text': 'Respuesta visible.'},
              ],
            },
          },
        ],
      });
      expect(extraerTextoGemini(body), 'Respuesta visible.');
    });
  });

  group('InterpretadorGemini.interpretar', () {
    test('devuelve el texto en el flujo feliz', () async {
      final cliente = MockClient((req) async {
        // Se envía la API key en el header y el prompt en el cuerpo.
        expect(req.headers['x-goog-api-key'], 'test-key');
        expect(req.body, contains('Alta corrosividad'));
        return http.Response(
          _respuestaGemini('Corrosividad alta; la conductividad es la '
              'variable determinante. Es una orientación preliminar.'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final interprete = InterpretadorGemini(cliente: cliente, apiKey: 'test-key');
      expect(interprete.disponible, isTrue);

      final texto = await interprete.interpretar(_datos);
      expect(texto, contains('orientación preliminar'));
    });

    test('lanza InterpretacionException si no hay conexión', () async {
      final cliente = MockClient((req) async {
        throw const _FalloDeRed();
      });
      final interprete = InterpretadorGemini(cliente: cliente, apiKey: 'test-key');
      expect(
        () => interprete.interpretar(_datos),
        throwsA(isA<InterpretacionException>()),
      );
    });

    test('lanza si la API responde con error HTTP', () async {
      final cliente = MockClient((req) async => http.Response('nope', 429));
      final interprete = InterpretadorGemini(cliente: cliente, apiKey: 'test-key');
      expect(
        () => interprete.interpretar(_datos),
        throwsA(isA<InterpretacionException>()),
      );
    });

    test('no está disponible ni intenta si falta la API key', () async {
      final interprete = InterpretadorGemini(apiKey: '   ');
      expect(interprete.disponible, isFalse);
      expect(
        () => interprete.interpretar(_datos),
        throwsA(isA<InterpretacionException>()),
      );
    });
  });
}

// Simula una caída de red (SocketException-like) sin depender de dart:io.
class _FalloDeRed implements Exception {
  const _FalloDeRed();
  @override
  String toString() => 'sin internet';
}
