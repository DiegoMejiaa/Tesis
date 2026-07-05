// =====================================================================
//  Miniatura y visor a pantalla completa de la foto de un punto
// ---------------------------------------------------------------------
//  Reutilizado por el diálogo de guardado (vista previa) y el historial
//  (miniatura + abrir en grande). Es tolerante: si la ruta es nula o el
//  archivo ya no existe, muestra un marcador neutro en vez de romperse.
// =====================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import '../tema/tema.dart';

/// Miniatura cuadrada de la foto en [ruta]. Si no hay foto o el archivo no
/// existe, muestra un marcador. Si [onTap] no es null y hay foto, es tocable.
Widget miniaturaFoto(
  BuildContext context,
  String? ruta, {
  double tam = 56,
  VoidCallback? onTap,
}) {
  final hayFoto = ruta != null && ruta.isNotEmpty && File(ruta).existsSync();
  final radio = BorderRadius.circular(12);

  Widget marcador(IconData icono) => Container(
        width: tam,
        height: tam,
        decoration: BoxDecoration(
          color: context.esquema.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: radio,
          border: Border.all(color: context.bordeSuave),
        ),
        child: Icon(icono, size: tam * 0.42, color: context.textoTenue),
      );

  final Widget contenido = hayFoto
      ? ClipRRect(
          borderRadius: radio,
          child: Image.file(
            File(ruta),
            width: tam,
            height: tam,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => marcador(Icons.broken_image_outlined),
          ),
        )
      : marcador(Icons.image_not_supported_outlined);

  if (onTap != null && hayFoto) {
    return InkWell(
      borderRadius: radio,
      onTap: onTap,
      child: contenido,
    );
  }
  return contenido;
}

/// Abre la foto en grande (zoom con InteractiveViewer) sobre fondo oscuro.
void abrirFotoCompleta(BuildContext context, String ruta) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _VisorFoto(ruta: ruta),
    ),
  );
}

class _VisorFoto extends StatelessWidget {
  const _VisorFoto({required this.ruta});

  final String ruta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto del punto'),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(
            File(ruta),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No se pudo abrir la foto (¿archivo movido o borrado?).',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
