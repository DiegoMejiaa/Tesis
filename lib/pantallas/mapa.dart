// =====================================================================
//  Pantalla de MAPA — puntos de medición georreferenciados (Módulo 1)
// ---------------------------------------------------------------------
//  Dibuja cada medición con coordenadas sobre un mapa de OpenStreetMap
//  (tiles sin API key). El marcador se colorea por clase de corrosividad
//  (verde = baja, ámbar = moderada, rojo = alta). Las mediciones sin
//  coordenadas simplemente no se dibujan. Al tocar un marcador se muestra
//  un resumen del punto (clase + resistividad).
// =====================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../datos/base_datos.dart';
import '../logica/corrosividad.dart';
import '../modelos/medicion.dart';
import '../tema/tema.dart';

class PantallaMapa extends StatefulWidget {
  const PantallaMapa({super.key, this.demo, this.tileProvider});

  /// Solo para previsualización/tests: si no es null, usa esta lista en vez de
  /// leer SQLite. En producción siempre es null.
  final List<Medicion>? demo;

  /// Proveedor de tiles. En producción es null y flutter_map usa el de red con
  /// caché en disco. En tests se inyecta uno sin caché (el caché usa
  /// path_provider, no disponible en el entorno de prueba).
  final TileProvider? tileProvider;

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

class _PantallaMapaState extends State<PantallaMapa> {
  // Centro por defecto (Ciudad Universitaria, UNAH · Tegucigalpa) cuando aún
  // no hay puntos georreferenciados que encuadrar.
  static const LatLng _centroPorDefecto = LatLng(14.0863, -87.1635);

  late Future<List<Medicion>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.demo != null
        ? Future.value(widget.demo)
        : BaseDatos.instancia.obtenerTodas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa de puntos')),
      body: FutureBuilder<List<Medicion>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final todas = snap.data ?? const <Medicion>[];
          final conCoords =
              todas.where((m) => m.tieneCoordenadas).toList(growable: false);
          return Stack(
            children: [
              _mapa(conCoords),
              _leyenda(),
              if (conCoords.isEmpty) _sinPuntos(),
            ],
          );
        },
      ),
    );
  }

  Widget _mapa(List<Medicion> puntos) {
    final coords = [
      for (final m in puntos) LatLng(m.latitud!, m.longitud!),
    ];
    return FlutterMap(
      options: _opciones(coords),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.monitoreo_suelo',
          maxZoom: 19,
          tileProvider: widget.tileProvider,
        ),
        MarkerLayer(
          markers: [
            for (final m in puntos) _marcador(m),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© OpenStreetMap'),
          ],
        ),
      ],
    );
  }

  MapOptions _opciones(List<LatLng> coords) {
    if (coords.isEmpty) {
      return const MapOptions(
        initialCenter: _centroPorDefecto,
        initialZoom: 6,
        minZoom: 2,
        maxZoom: 19,
      );
    }
    // Centro en el centroide de los puntos y zoom de vecindario. (Se prefiere a
    // CameraFit.coordinates porque este último depende de un pase de layout que
    // no ocurre en el render de prueba y dejaría los marcadores fuera de vista.)
    var lat = 0.0, lon = 0.0;
    for (final c in coords) {
      lat += c.latitude;
      lon += c.longitude;
    }
    final centro = LatLng(lat / coords.length, lon / coords.length);
    return MapOptions(
      initialCenter: centro,
      initialZoom: coords.length == 1 ? 16 : 15,
      minZoom: 2,
      maxZoom: 19,
    );
  }

  Marker _marcador(Medicion m) {
    final color = colorCategoria(m.condicion, context.brillo);
    return Marker(
      point: LatLng(m.latitud!, m.longitud!),
      width: 44,
      height: 44,
      alignment: Alignment.bottomCenter, // la punta del pin marca el punto
      child: GestureDetector(
        onTap: () => _mostrarDetalle(m),
        child: Icon(
          Icons.location_on,
          color: color,
          size: 40,
          shadows: const [
            Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalle(Medicion m) {
    final color = colorCategoria(m.condicion, context.brillo);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${m.terreno} · Punto ${m.punto}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              m.fechaLegible,
              style: TextStyle(fontSize: 12, color: ctx.textoTenue),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                nombreCorrosividad(m.condicion),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _dato('Humedad', m.humedad, '%'),
                _dato('CE', m.ce, 'µS/cm', decimales: 0),
                _datoTexto('Resistividad', resistividadTexto(m.ce)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Lat ${m.latitud!.toStringAsFixed(5)}, '
              'Lon ${m.longitud!.toStringAsFixed(5)}',
              style: TextStyle(
                fontSize: 12,
                color: ctx.textoTenue,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Leyenda de colores por clase de corrosividad.
  Widget _leyenda() {
    Widget fila(String etiqueta, String categoria) {
      final color = colorCategoria(categoria, context.brillo);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, size: 16, color: color),
            const SizedBox(width: 6),
            Text(etiqueta, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return Positioned(
      left: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colorTarjeta.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.bordeSuave),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fila('Baja corrosividad', 'normal'),
            fila('Corrosividad moderada', 'moderado'),
            fila('Alta corrosividad', 'crítico'),
          ],
        ),
      ),
    );
  }

  Widget _sinPuntos() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.colorTarjeta.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.bordeSuave),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, color: context.textoTenue),
            const SizedBox(height: 10),
            Text(
              'Todavía no hay puntos con ubicación.\n'
              'Guardá una medición con el GPS activo para verla acá.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textoTenue, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, double? valor, String unidad,
      {int decimales = 1}) {
    final texto = valor == null ? '—' : valor.toStringAsFixed(decimales);
    return _datoTexto(etiqueta, '$texto $unidad');
  }

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
}
