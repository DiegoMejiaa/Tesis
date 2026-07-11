// =====================================================================
//  Tema visual de la app (Material 3) — claro y oscuro
// ---------------------------------------------------------------------
//  Paleta agro/suelo derivada de un verde semilla. Ambos temas comparten
//  la misma identidad; solo cambian fondo, tarjetas y contraste. Los
//  widgets deben leer sus colores del Theme (no hardcodear) para que el
//  modo oscuro se vea correcto.
// =====================================================================

import 'package:flutter/material.dart';

// Semilla agro (verde suelo). Toda la app deriva de acá.
const semillaVerde = Color(0xFF2E7D32);

// Acentos por variable medida. Se usan como tinte de ícono/chip sobre fondos
// translúcidos, así que se leen bien tanto en claro como en oscuro.
const acentoHumedad = Color(0xFF3B82F6); // azul
const acentoTemperatura = Color(0xFFF2811D); // naranja
const acentoCE = Color(0xFF8B5CF6); // morado
const acentoPH = Color(0xFF14B8A6); // verde azulado

ThemeData temaClaro() => _construir(Brightness.light);
ThemeData temaOscuro() => _construir(Brightness.dark);

ThemeData _construir(Brightness brillo) {
  final esOscuro = brillo == Brightness.dark;
  final esquema = ColorScheme.fromSeed(
    seedColor: semillaVerde,
    brightness: brillo,
  );
  final fondo = esOscuro ? const Color(0xFF11150F) : const Color(0xFFF3F6F2);
  final tarjeta = esOscuro ? const Color(0xFF1B211A) : Colors.white;
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: fondo,
    cardColor: tarjeta,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: fondo,
      foregroundColor: esquema.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(
      color: esquema.outlineVariant.withValues(alpha: 0.5),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

// Color de la condición preliminar (Módulo 3), legible en ambos temas.
Color colorCategoria(String? categoria, Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  switch (categoria) {
    case 'crítico':
    case 'critico':
      return oscuro ? const Color(0xFFFF7A5E) : const Color(0xFFE0563B);
    case 'moderado':
      return oscuro ? const Color(0xFFFFC24B) : const Color(0xFFE59A1F);
    case 'normal':
      return oscuro ? const Color(0xFF6DD47E) : const Color(0xFF2E7D32);
    default:
      return oscuro ? const Color(0xFF9AA79A) : const Color(0xFF7A857A);
  }
}

// Atajos semánticos para no repetir Theme.of(context)... en cada widget.
extension ColoresApp on BuildContext {
  ColorScheme get esquema => Theme.of(this).colorScheme;
  Brightness get brillo => Theme.of(this).brightness;
  Color get colorTarjeta => Theme.of(this).cardColor;
  Color get textoFuerte => Theme.of(this).colorScheme.onSurface;
  Color get textoTenue => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get bordeSuave =>
      Theme.of(this).colorScheme.outlineVariant.withValues(alpha: 0.5);
}
