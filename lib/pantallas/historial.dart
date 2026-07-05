// =====================================================================
//  Pantalla de Historial — Módulo 2
// ---------------------------------------------------------------------
//  Muestra las mediciones guardadas (dataset piloto), permite borrarlas
//  y exportar todo a CSV (se copia al portapapeles para pegar en Excel).
//  Los colores salen del Theme (tema.dart) para verse bien en claro/oscuro.
// =====================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../datos/base_datos.dart';
import '../modelos/medicion.dart';
import '../tema/tema.dart';
import 'vista_foto.dart';

class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key, this.demo});

  /// Solo para previsualización/capturas: si no es null, muestra esta lista en
  /// vez de leer SQLite. En producción siempre es null.
  final List<Medicion>? demo;

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  late Future<List<Medicion>> _futuro;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    _futuro = widget.demo != null
        ? Future.value(widget.demo)
        : BaseDatos.instancia.obtenerTodas();
  }

  Future<void> _borrar(Medicion m) async {
    if (m.id == null) return;
    await BaseDatos.instancia.borrar(m.id!);
    setState(_recargar);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Medición eliminada')));
    }
  }

  Future<void> _exportar() async {
    final csv = await BaseDatos.instancia.exportarCsv();
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV copiado al portapapeles. Pégalo en Excel/Sheets.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de mediciones'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportar,
          ),
        ],
      ),
      body: FutureBuilder<List<Medicion>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No se pudo leer el historial.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textoTenue),
                ),
              ),
            );
          }
          final lista = snap.data ?? const [];
          if (lista.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aún no hay mediciones guardadas.\n'
                  'Conéctate al sensor y pulsa "Guardar medición".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textoTenue),
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Text(
                      '${lista.length} '
                      '${lista.length == 1 ? "registro" : "registros"}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.textoTenue,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: lista.length,
                  itemBuilder: (context, i) => _tarjetaMedicion(lista[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjetaMedicion(Medicion m) {
    final tieneFoto = m.foto != null && m.foto!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorTarjeta,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.bordeSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tieneFoto) ...[
                miniaturaFoto(
                  context,
                  m.foto,
                  tam: 52,
                  onTap: () => abrirFotoCompleta(context, m.foto!),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.terreno} · Punto ${m.punto}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textoFuerte,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.fechaLegible,
                      style: TextStyle(fontSize: 12, color: context.textoTenue),
                    ),
                  ],
                ),
              ),
              if (m.condicion != null) _chipCondicion(m.condicion!),
              IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline, size: 20),
                color: context.textoTenue,
                onPressed: () => _borrar(m),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _dato('Humedad', m.humedad, '%'),
              _dato('Temp', m.temperatura, '°C'),
              _dato('CE', m.ce, 'µS/cm', decimales: 0),
            ],
          ),
          if (m.observaciones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Obs: ${m.observaciones}',
              style: TextStyle(fontSize: 12, color: context.textoTenue),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipCondicion(String condicion) {
    final color = colorCategoria(condicion, context.brillo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        condicion,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, double? valor, String unidad,
      {int decimales = 1}) {
    final texto = valor == null ? '—' : valor.toStringAsFixed(decimales);
    // Text.rich (no RichText) para heredar la fuente del tema (Roboto).
    return Text.rich(
      TextSpan(
        style: TextStyle(color: context.textoFuerte),
        children: [
          TextSpan(
            text: '$etiqueta: ',
            style: TextStyle(fontSize: 12, color: context.textoTenue),
          ),
          TextSpan(
            text: '$texto $unidad',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
