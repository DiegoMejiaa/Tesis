// =====================================================================
//  Controlador del modo de tema (sistema / claro / oscuro)
// ---------------------------------------------------------------------
//  ChangeNotifier que recuerda la preferencia del usuario con
//  shared_preferences. Por defecto sigue el tema del sistema. La lógica es
//  testeable sin dispositivo usando SharedPreferences.setMockInitialValues.
// =====================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControladorTema extends ChangeNotifier {
  static const clavePrefs = 'tema_modo';

  ThemeMode _modo = ThemeMode.system;
  ThemeMode get modo => _modo;

  // Lee la preferencia guardada (si existe). Llamar al arrancar la app.
  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _modo = _desdeTexto(prefs.getString(clavePrefs));
    notifyListeners();
  }

  // Fija un modo y lo persiste.
  Future<void> fijar(ThemeMode modo) async {
    if (modo == _modo) return;
    _modo = modo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clavePrefs, _aTexto(modo));
  }

  // Cicla sistema -> claro -> oscuro -> sistema (para el botón del encabezado).
  Future<void> ciclar() => fijar(siguiente(_modo));

  static ThemeMode siguiente(ThemeMode m) => switch (m) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };

  static String _aTexto(ThemeMode m) => switch (m) {
        ThemeMode.light => 'claro',
        ThemeMode.dark => 'oscuro',
        ThemeMode.system => 'sistema',
      };

  static ThemeMode _desdeTexto(String? s) => switch (s) {
        'claro' => ThemeMode.light,
        'oscuro' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
