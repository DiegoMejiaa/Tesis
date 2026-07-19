// =====================================================================
//  Pantalla de Historial — Módulo 2
// ---------------------------------------------------------------------
//  Muestra las mediciones guardadas (dataset piloto), permite borrarlas
//  y exportar todo a CSV (se copia al portapapeles para pegar en Excel).
//  Los colores salen del Theme (tema.dart) para verse bien en claro/oscuro.
// =====================================================================

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../datos/base_datos.dart';
import '../logica/clasificador_difuso.dart';
import '../logica/corrosividad.dart';
import '../logica/interpretador_llm.dart';
import '../logica/reporte_pdf.dart';
import '../logica/selector_foto.dart';
import '../modelos/medicion.dart';
import '../tema/tema.dart';
import 'mapa.dart';
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

  // Interpretación de apoyo (capa de presentación). Se usa solo para el botón
  // "Generar interpretación" de las mediciones que se guardaron sin ella (p. ej.
  // sin conexión). El texto ya guardado se muestra sin necesidad de red.
  final InterpretadorLLM _interpretador = InterpretadorGemini();
  final Set<int> _generandoIds = {}; // ids con una generación en curso

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

  // Respaldo completo con un toque: (a) copia el CSV del historial al
  // portapapeles y (b) copia TODAS las fotos referenciadas en la base a la
  // galería pública (álbum "monitoreo_suelo"), para que sobrevivan a una
  // reinstalación y queden respaldadas en la nube. Cada foto se guarda como
  // "<terreno>_<punto>_<fecha>.jpg".
  Future<void> _exportarRespaldo() async {
    final lista = widget.demo ?? await BaseDatos.instancia.obtenerTodas();

    // (a) CSV del historial al portapapeles.
    final csv = await BaseDatos.instancia.exportarCsv();
    await Clipboard.setData(ClipboardData(text: csv));

    // (b) Fotos referenciadas -> galería pública.
    var conFoto = 0, respaldadas = 0;
    for (final m in lista) {
      final ruta = m.foto;
      if (ruta == null || ruta.isEmpty || !File(ruta).existsSync()) continue;
      conFoto++;
      if (await guardarFotoEnGaleria(ruta, nombre: _nombrePublico(m))) {
        respaldadas++;
      }
    }

    if (!mounted) return;
    final String msg;
    if (conFoto == 0) {
      msg = 'CSV copiado al portapapeles. No hay fotos que respaldar.';
    } else if (respaldadas == conFoto) {
      msg = 'Respaldo listo: CSV copiado y $respaldadas '
          '${respaldadas == 1 ? "foto guardada" : "fotos guardadas"} '
          'en Galería › $albumGaleria.';
    } else {
      msg = 'CSV copiado. Se respaldaron $respaldadas de $conFoto fotos en '
          'Galería › $albumGaleria (revisá el permiso de galería).';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Importa el historial desde un CSV elegido por el usuario. Reinserta las
  // mediciones (recalculando la condición con el clasificador actual), evita
  // duplicados por fecha_hora y refresca la lista. Ver BaseDatos.importarCsv.
  Future<void> _importarCsv() async {
    FilePickerResult? seleccion;
    try {
      seleccion = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // trae los bytes (más confiable que la ruta en Android)
      );
    } catch (e) {
      _aviso('No se pudo abrir el selector de archivos: $e');
      return;
    }
    if (seleccion == null || seleccion.files.isEmpty) return; // cancelado

    final archivo = seleccion.files.single;
    String? contenido;
    try {
      if (archivo.bytes != null) {
        contenido = utf8.decode(archivo.bytes!, allowMalformed: true);
      } else if (archivo.path != null) {
        contenido = await File(archivo.path!).readAsString();
      }
    } catch (e) {
      _aviso('No se pudo leer el archivo: $e');
      return;
    }
    if (contenido == null) {
      _aviso('No se pudo leer el archivo seleccionado.');
      return;
    }

    final int importadas;
    try {
      importadas = await BaseDatos.instancia.importarCsv(contenido);
    } catch (e) {
      _aviso('Error al importar el CSV: $e');
      return;
    }

    if (!mounted) return;
    setState(_recargar);
    _aviso('$importadas mediciones importadas');
  }

  // Genera un PDF con la tabla de puntos (por grupo campo/controles/banco) y un
  // resumen, y abre el diálogo del sistema para compartirlo/guardarlo. Es solo
  // presentación: usa el clasificador actual en modo lectura.
  Future<void> _exportarReporte() async {
    final lista = widget.demo ?? await BaseDatos.instancia.obtenerTodas();
    if (lista.isEmpty) {
      _aviso('No hay mediciones para incluir en el reporte.');
      return;
    }
    try {
      final bytes = await construirReportePdf(lista);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'reporte_corrosividad.pdf',
      );
    } catch (e) {
      _aviso('No se pudo generar el reporte: $e');
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Nombre público "<terreno>_<punto>_<fecha>" saneado (sin espacios ni
  // caracteres que rompan un nombre de archivo).
  String _nombrePublico(Medicion m) {
    String limpio(String s) {
      final r = s.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      return r.isEmpty ? 'x' : r;
    }

    String dos(int n) => n.toString().padLeft(2, '0');
    final d = DateTime.tryParse(m.fechaHora);
    final fecha = d == null
        ? limpio(m.fechaHora)
        : '${d.year}${dos(d.month)}${dos(d.day)}_'
            '${dos(d.hour)}${dos(d.minute)}${dos(d.second)}';
    return '${limpio(m.terreno)}_${limpio(m.punto)}_$fecha';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de mediciones'),
        actions: [
          IconButton(
            tooltip: 'Mapa de puntos',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PantallaMapa(demo: widget.demo),
              ),
            ),
          ),
          // Acciones de datos agrupadas en un menú para no saturar la barra
          // (importar/exportar CSV, reporte PDF y respaldo).
          PopupMenuButton<String>(
            tooltip: 'Datos y exportación',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'importar':
                  _importarCsv();
                case 'csv':
                  _exportar();
                case 'reporte':
                  _exportarReporte();
                case 'respaldo':
                  _exportarRespaldo();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'importar',
                child: ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('Importar CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Exportar CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'reporte',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Exportar reporte (PDF)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'respaldo',
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Exportar respaldo (CSV + fotos)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
    // Score recalculado con el clasificador actual (solo presentación; no
    // altera lo guardado). Requiere humedad y CE para poder inferir.
    final clas = (m.humedad != null && m.ce != null)
        ? clasificar(humedad: m.humedad!, ce: m.ce!, temperatura: m.temperatura)
        : null;
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
              _datoTexto('Resistividad', resistividadTexto(m.ce)),
              if (clas != null)
                _datoTexto('Score', '${clas.score.round()}/100'),
            ],
          ),
          if (m.observaciones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Obs: ${m.observaciones}',
              style: TextStyle(fontSize: 12, color: context.textoTenue),
            ),
          ],
          _seccionInterpretacion(m, clas),
        ],
      ),
    );
  }

  // Muestra la interpretación de apoyo GUARDADA (si existe) con su etiqueta y
  // descargos. Si no hay y hay datos suficientes + API key, ofrece un botón para
  // generarla ahora (útil para mediciones guardadas sin conexión). En modo demo
  // no se muestra el botón (no hay red).
  Widget _seccionInterpretacion(Medicion m, Clasificacion? clas) {
    final texto = m.interpretacion;
    if (texto != null && texto.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Divider(height: 1, color: context.bordeSuave),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 14, color: context.textoTenue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Interpretación de apoyo (orientación preliminar)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.textoTenue,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            style: TextStyle(
                fontSize: 13, height: 1.35, color: context.textoFuerte),
          ),
          const SizedBox(height: 6),
          Text(
            'Texto generado por IA como apoyo; no sustituye un estudio '
            'especializado ni el criterio profesional.',
            style: TextStyle(
              fontSize: 10.5,
              color: context.textoTenue,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    // Sin interpretación guardada: botón para generarla (solo con datos reales,
    // clasificación disponible y API key configurada).
    if (widget.demo == null &&
        clas != null &&
        m.id != null &&
        _interpretador.disponible) {
      final generando = _generandoIds.contains(m.id);
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: generando ? null : () => _generarInterpretacion(m, clas),
          icon: generando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 16),
          label: Text(generando ? 'Generando…' : 'Generar interpretación'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Genera la interpretación de una medición ya guardada y la persiste. Si no
  // hay conexión o falla, avisa discretamente y no cambia nada (no crashea).
  Future<void> _generarInterpretacion(Medicion m, Clasificacion clas) async {
    if (m.id == null) return;
    setState(() => _generandoIds.add(m.id!));
    final datos = DatosInterpretacion(
      clase: nombreCorrosividad(clas.categoria),
      score: clas.score.round(),
      ce: m.ce,
      resistividad: resistividadOhmCm(m.ce),
      humedad: m.humedad,
      temperatura: m.temperatura,
      ph: m.ph,
      variablesAltas: clas.variablesAlteradas,
    );
    String? texto;
    try {
      texto = await _interpretador.interpretar(datos);
      await BaseDatos.instancia.actualizarInterpretacion(m.id!, texto);
    } catch (_) {
      texto = null;
    }
    if (!mounted) return;
    setState(() {
      _generandoIds.remove(m.id!);
      if (texto != null) _recargar();
    });
    if (texto == null) {
      _aviso('No se pudo generar la interpretación (revisá la conexión).');
    }
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
        nombreCorrosividad(condicion),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // Igual que _dato pero con un valor de texto ya formateado (resistividad,
  // score). Hereda la fuente del tema para verse consistente.
  Widget _datoTexto(String etiqueta, String valor) {
    return Text.rich(
      TextSpan(
        style: TextStyle(color: context.textoFuerte),
        children: [
          TextSpan(
            text: '$etiqueta: ',
            style: TextStyle(fontSize: 12, color: context.textoTenue),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
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
