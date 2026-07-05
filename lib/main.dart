// =====================================================================
//  App de Monitoreo Preventivo del Suelo  —  MÓDULO 1
//  Conexión Bluetooth (SPP) con la ESP32 + lectura en vivo
// ---------------------------------------------------------------------
//  Lee el JSON que envía la ESP32 (ESP32_Suelo) y muestra en pantalla
//  humedad, temperatura y conductividad eléctrica (CE).
//  (pH y NPK se omiten de las tarjetas: no son confiables en este sensor.)
// =====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'datos/base_datos.dart';
import 'logica/clasificador_difuso.dart';
import 'logica/contador_guardadas.dart';
import 'logica/parseo_lectura.dart';
import 'logica/selector_foto.dart';
import 'modelos/medicion.dart';
import 'pantallas/historial.dart';
import 'pantallas/vista_foto.dart';
import 'tema/controlador_tema.dart';
import 'tema/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controladorTema = ControladorTema();
  await controladorTema.cargar(); // aplica la preferencia guardada al arrancar
  runApp(MonitoreoApp(controladorTema: controladorTema));
}

class MonitoreoApp extends StatelessWidget {
  const MonitoreoApp({super.key, required this.controladorTema});

  final ControladorTema controladorTema;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controladorTema,
      builder: (context, _) => MaterialApp(
        title: 'Monitoreo de Suelo',
        debugShowCheckedModeBanner: false,
        theme: temaClaro(),
        darkTheme: temaOscuro(),
        themeMode: controladorTema.modo,
        home: PantallaLecturas(controladorTema: controladorTema),
      ),
    );
  }
}

class PantallaLecturas extends StatefulWidget {
  const PantallaLecturas({
    super.key,
    this.datosDemo,
    this.controladorTema,
    this.selectorFoto,
  });

  /// Solo para previsualización/capturas (golden tests). Si no es null, la
  /// pantalla NO usa Bluetooth y muestra estos valores de ejemplo. En
  /// producción siempre es null.
  final Map<String, Object?>? datosDemo;

  /// Control del tema para el botón del encabezado (null en previsualización).
  final ControladorTema? controladorTema;

  /// Acceso a la cámara/galería. Inyectable para poder mockearlo en tests; en
  /// producción es null y se usa la implementación real (image_picker).
  final SelectorFoto? selectorFoto;

  @override
  State<PantallaLecturas> createState() => _PantallaLecturasState();
}

class _PantallaLecturasState extends State<PantallaLecturas> {
  // --- Estado de Bluetooth ---
  List<BluetoothDevice> _dispositivos = [];
  BluetoothDevice? _seleccionado;
  BluetoothConnection? _conexion;
  bool _conectando = false;
  bool _conectado = false;
  String _estado = 'Desconectado';
  bool _hayError = false; // resalta el chip de estado en rojo
  String _buffer = ''; // acumula bytes hasta encontrar un salto de línea

  // --- Últimas lecturas recibidas ---
  String _punto = '-';
  double? _humedad;
  double? _temperatura;
  double? _ce;
  double?
  _ph; // pH crudo: se guarda para reanálisis, no se muestra en tarjetas.
  int? _nLecturas; // "promedio de muestras" del firmware (no es un contador).
  String _ultimoCrudo = '';

  // Contador REAL de mediciones guardadas en el punto/terreno actual. Es
  // distinto de _nLecturas: sube +1 por cada medición guardada y se reinicia
  // al cambiar de punto o de terreno.
  final ContadorGuardadas _contadorGuardadas = ContadorGuardadas();
  int _guardadasEnPunto = 0;

  // Acceso a cámara/galería (real por defecto, mockeable en tests).
  late final SelectorFoto _selectorFoto =
      widget.selectorFoto ?? SelectorFotoImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.datosDemo != null) {
      _cargarDemo(widget.datosDemo!);
    } else {
      _inicializar();
    }
  }

  // Carga datos de ejemplo para previsualización (sin tocar Bluetooth).
  void _cargarDemo(Map<String, Object?> d) {
    final nombre = d['dispositivo'] as String?;
    if (nombre != null) {
      final dev = BluetoothDevice(name: nombre, address: '00:11:22:33:44:55');
      _dispositivos = [dev];
      _seleccionado = dev;
    }
    _conectado = d['conectado'] == true;
    _estado = (d['estado'] as String?) ?? 'Desconectado';
    _hayError = d['error'] == true;
    _punto = (d['punto'] as String?) ?? '-';
    _humedad = (d['humedad'] as num?)?.toDouble();
    _temperatura = (d['temperatura'] as num?)?.toDouble();
    _ce = (d['ce'] as num?)?.toDouble();
    _nLecturas = (d['n_lecturas'] as num?)?.toInt();
    _guardadasEnPunto = (d['guardadas'] as num?)?.toInt() ?? 0;
    _ultimoCrudo = (d['crudo'] as String?) ?? '';
  }

  Future<void> _inicializar() async {
    await _pedirPermisos();
    await _cargarDispositivos();
  }

  // Android 12+ exige permisos en tiempo de ejecución para Bluetooth
  Future<void> _pedirPermisos() async {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
  }

  // Lista los dispositivos ya emparejados (ESP32_Suelo debe estar aquí)
  Future<void> _cargarDispositivos() async {
    try {
      final enlazados = await FlutterBluetoothSerial.instance
          .getBondedDevices();
      setState(() {
        _dispositivos = enlazados;
        // La selección debe SIEMPRE ser un dispositivo presente en la lista; si
        // no, el DropdownButton lanza una aserción y la app crashea (p. ej. al
        // "Olvidar" la ESP32 que estaba seleccionada).
        BluetoothDevice? sel;
        for (final d in enlazados) {
          if ((d.name ?? '').contains('ESP32')) {
            sel = d;
            break;
          }
        }
        // Conserva la selección previa solo si sigue emparejada.
        if (sel == null &&
            _seleccionado != null &&
            enlazados.any((d) => d.address == _seleccionado!.address)) {
          sel = _seleccionado;
        }
        sel ??= enlazados.isNotEmpty ? enlazados.first : null;
        _seleccionado = sel;
      });
    } catch (e) {
      setState(() {
        _estado = 'Error al listar dispositivos: $e';
        _hayError = true;
      });
    }
  }

  Future<void> _conectar() async {
    if (_seleccionado == null) return;
    setState(() {
      _conectando = true;
      _hayError = false;
      _estado = 'Conectando...';
    });
    try {
      // Timeout: si la ESP32 está apagada/fuera de rango, no dejamos la UI
      // colgada esperando indefinidamente.
      final c = await BluetoothConnection.toAddress(
        _seleccionado!.address,
      ).timeout(const Duration(seconds: 12));
      _conexion = c;
      setState(() {
        _conectado = true;
        _conectando = false;
        _hayError = false;
        _estado =
            'Conectado a ${_seleccionado!.name ?? _seleccionado!.address}';
      });
      // Escucha continua; maneja tanto el cierre normal como un error de flujo
      // (cable/rango) sin crashear y dejando la UI lista para reconectar.
      c.input!
          .listen(
            _onDatos,
            cancelOnError: true,
            onError: (Object e) => _marcarDesconectado('Conexión interrumpida'),
          )
          .onDone(() => _marcarDesconectado('Desconectado'));
    } on TimeoutException {
      setState(() {
        _conectando = false;
        _hayError = true;
        _estado = 'Tiempo de espera agotado. ¿La ESP32 está encendida?';
      });
    } catch (e) {
      setState(() {
        _conectando = false;
        _hayError = true;
        _estado = 'No se pudo conectar: $e';
      });
    }
  }

  // Deja la UI en estado desconectado (sin crashear) tras un cierre o error.
  void _marcarDesconectado(String mensaje) {
    if (!mounted) return;
    setState(() {
      _conectado = false;
      _conectando = false;
      _estado = mensaje;
      _hayError = mensaje != 'Desconectado';
    });
  }

  // Acumula bytes y procesa línea por línea (cada \n)
  void _onDatos(Uint8List datos) {
    _buffer += utf8.decode(datos, allowMalformed: true);
    int idx;
    while ((idx = _buffer.indexOf('\n')) >= 0) {
      final linea = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (linea.isNotEmpty) _procesarLinea(linea);
    }
  }

  // Interpreta una línea usando el parser tolerante (nunca crashea con JSON
  // malformado o incompleto). Ver logica/parseo_lectura.dart.
  void _procesarLinea(String linea) {
    setState(() => _ultimoCrudo = linea);
    final lectura = parsearLectura(linea);
    if (lectura == null) return; // texto suelto / JSON incompleto: se ignora
    if (lectura.esError) {
      setState(() {
        _estado = 'Sensor sin respuesta (revisar 12V / cableado)';
        _hayError = true;
      });
      return;
    }
    setState(() {
      _hayError = false;
      _punto = lectura.punto ?? _punto;
      _humedad = lectura.humedad;
      _temperatura = lectura.temperatura;
      _ce = lectura.ce;
      // pH crudo: se captura y se guarda, pero NO se muestra en las tarjetas
      // principales ni entra en la clasificación difusa (Módulo 3).
      _ph = lectura.ph;
      _nLecturas = lectura.nLecturas;
    });
  }

  Future<void> _desconectar() async {
    await _conexion?.close();
    _marcarDesconectado('Desconectado');
  }

  @override
  void dispose() {
    _conexion?.dispose();
    super.dispose();
  }

  // ===================================================================
  //  Módulo 2: guardar en el historial / dataset piloto
  // ===================================================================

  // Hay algo que valga la pena guardar si llegó al menos una variable.
  bool get _hayLectura =>
      _humedad != null || _temperatura != null || _ce != null;

  // Clasificación difusa en vivo (Módulo 3); null si faltan humedad o CE.
  Clasificacion? get _clasificacion {
    if (_humedad == null || _ce == null) return null;
    return clasificar(humedad: _humedad!, ce: _ce!, temperatura: _temperatura);
  }

  // Abre un diálogo para capturar terreno/punto/observaciones y guarda.
  Future<void> _guardarMedicion() async {
    if (!_hayLectura) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay lecturas para guardar todavía.')),
      );
      return;
    }
    final terrenoCtrl = TextEditingController();
    final puntoCtrl = TextEditingController(text: _punto == '-' ? '' : _punto);
    final obsCtrl = TextEditingController();
    String? fotoRuta; // foto opcional del punto (ruta local ya persistida)

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Guardar medición'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: terrenoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terreno *',
                    hintText: 'Ej. Terreno A',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: puntoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Punto *',
                    hintText: 'Ej. P1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                _seccionFotoDialog(
                  ctx,
                  fotoRuta,
                  (nueva) => setDlg(() => fotoRuta = nueva),
                ),
                const SizedBox(height: 16),
                _resumenLecturaDialog(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardar != true) return;
    final terreno = terrenoCtrl.text.trim();
    final punto = puntoCtrl.text.trim();
    if (terreno.isEmpty || punto.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indica al menos el terreno y el punto.'),
          ),
        );
      }
      return;
    }

    // Módulo 3: clasifica la lectura y guarda la categoría en "condicion".
    final categoria = (_humedad != null && _ce != null)
        ? clasificar(
            humedad: _humedad!,
            ce: _ce!,
            temperatura: _temperatura,
          ).categoria
        : null;

    final m = Medicion(
      terreno: terreno,
      punto: punto,
      fechaHora: DateTime.now().toIso8601String(),
      humedad: _humedad,
      temperatura: _temperatura,
      ce: _ce,
      ph: _ph, // se registra el pH crudo aunque no se muestre en pantalla
      nLecturas: _nLecturas,
      observaciones: obsCtrl.text.trim(),
      condicion: categoria,
      foto: fotoRuta,
    );
    try {
      await BaseDatos.instancia.insertar(m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la medición: $e')),
        );
      }
      return;
    }
    // Suma al contador de mediciones guardadas del punto (se reinicia solo si
    // cambió el terreno o el punto respecto de la última medición guardada).
    final total = _contadorGuardadas.registrar(terreno, punto);
    if (mounted) {
      setState(() => _guardadasEnPunto = total);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medición guardada en el historial.')),
      );
    }
  }

  // Resumen de la lectura actual dentro del diálogo de guardado.
  Widget _resumenLecturaDialog() {
    String f(double? v, [int d = 1]) => v == null ? '—' : v.toStringAsFixed(d);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.esquema.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Humedad: ${f(_humedad)} %   ·   Temp: ${f(_temperatura)} °C   ·   '
        'CE: ${f(_ce, 0)} µS/cm',
        style: TextStyle(fontSize: 12, color: context.textoTenue),
      ),
    );
  }

  // Sección de foto dentro del diálogo de guardado. Si aún no hay foto, muestra
  // botones de Cámara/Galería; si ya hay, muestra la miniatura y "Quitar". El
  // acceso al dispositivo pasa por _selectorFoto (mockeable).
  Widget _seccionFotoDialog(
    BuildContext dctx,
    String? ruta,
    void Function(String?) onCambio,
  ) {
    Future<void> elegir(OrigenFoto origen) async {
      try {
        final r = await _selectorFoto.capturar(origen);
        if (r != null) onCambio(r);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo obtener la foto: $e')),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto del punto (opcional)',
          style: TextStyle(
            fontSize: 12,
            color: context.textoTenue,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (ruta == null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => elegir(OrigenFoto.camara),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => elegir(OrigenFoto.galeria),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galería'),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              miniaturaFoto(
                dctx,
                ruta,
                tam: 64,
                onTap: () => abrirFotoCompleta(dctx, ruta),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Foto adjunta',
                  style: TextStyle(fontSize: 13, color: context.textoFuerte),
                ),
              ),
              TextButton.icon(
                onPressed: () => onCambio(null),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar'),
              ),
            ],
          ),
      ],
    );
  }

  void _abrirHistorial() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PantallaHistorial()));
  }

  // ===================================================================
  //  UI
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _encabezado(),
            const SizedBox(height: 20),
            _panelConexion(),
            const SizedBox(height: 28),
            _tituloSeccion(),
            const SizedBox(height: 12),
            _tarjetaMetrica(
              'Humedad',
              _humedad,
              '%',
              Icons.water_drop_outlined,
              acentoHumedad,
            ),
            _tarjetaMetrica(
              'Temperatura',
              _temperatura,
              '°C',
              Icons.thermostat,
              acentoTemperatura,
            ),
            _tarjetaMetrica(
              'Conductividad',
              _ce,
              'µS/cm',
              Icons.bolt_outlined,
              acentoCE,
              decimales: 0,
            ),
            const SizedBox(height: 16),
            _bannerCondicion(),
            const SizedBox(height: 16),
            _botonGuardar(),
            const SizedBox(height: 16),
            _lineaCruda(),
          ],
        ),
      ),
    );
  }

  // --- Encabezado: logo + título + tema + historial + recargar ---
  Widget _encabezado() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.esquema.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.eco, color: context.esquema.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monitoreo de Suelo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(
                'Lectura en vivo · ESP32',
                style: TextStyle(fontSize: 13, color: context.textoTenue),
              ),
            ],
          ),
        ),
        _botonTema(),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Historial',
          icon: const Icon(Icons.history),
          onPressed: _abrirHistorial,
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Recargar dispositivos',
          icon: const Icon(Icons.refresh),
          onPressed: _cargarDispositivos,
        ),
      ],
    );
  }

  // Botón para alternar tema (sistema → claro → oscuro). Deshabilitado en
  // previsualización, donde no hay controlador.
  Widget _botonTema() {
    final controlador = widget.controladorTema;
    final modo = controlador?.modo ?? ThemeMode.system;
    final (icono, etiqueta) = switch (modo) {
      ThemeMode.system => (Icons.brightness_auto_outlined, 'Tema: sistema'),
      ThemeMode.light => (Icons.light_mode_outlined, 'Tema: claro'),
      ThemeMode.dark => (Icons.dark_mode_outlined, 'Tema: oscuro'),
    };
    return IconButton.filledTonal(
      tooltip: '$etiqueta (tocar para cambiar)',
      icon: Icon(icono),
      onPressed: controlador?.ciclar,
    );
  }

  // --- Panel: selector de dispositivo, botón y estado ---
  Widget _panelConexion() {
    return _tarjeta(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.esquema.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<BluetoothDevice>(
                      isExpanded: true,
                      value: _seleccionado,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      hint: const Text('Selecciona un dispositivo'),
                      borderRadius: BorderRadius.circular(14),
                      items: _dispositivos
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                d.name ?? d.address,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _conectado
                          ? null
                          : (d) => setState(() => _seleccionado = d),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _botonConectar(),
            ],
          ),
          const SizedBox(height: 14),
          _chipEstado(),
        ],
      ),
    );
  }

  Widget _botonConectar() {
    if (_conectando) {
      return const SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _conectado ? _desconectar : _conectar,
        style: FilledButton.styleFrom(
          backgroundColor: _conectado
              ? context.esquema.error
              : context.esquema.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Text(_conectado ? 'Desconectar' : 'Conectar'),
      ),
    );
  }

  // Pastilla de estado con color según conexión (verde/ámbar/rojo/gris).
  Widget _chipEstado() {
    final Color color = _hayError
        ? context.esquema.error
        : _conectado
        ? colorCategoria('normal', context.brillo)
        : _conectando
        ? acentoTemperatura
        : context.textoTenue;
    final IconData icono = _hayError
        ? Icons.error_outline
        : _conectado
        ? Icons.bluetooth_connected
        : _conectando
        ? Icons.bluetooth_searching
        : Icons.bluetooth_disabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _estado,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Título de sección con el punto, el promedio de muestras y el contador ---
  Widget _tituloSeccion() {
    // n_lecturas del firmware = cuántas muestras promedió la ESP32 por lectura
    // (siempre 5). NO es un contador de mediciones: por eso se rotula como
    // "promedio de N muestras" y el contador real va aparte, abajo.
    final resumenPunto = _nLecturas != null
        ? 'Punto $_punto · promedio de $_nLecturas muestras'
        : 'Punto $_punto';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Lecturas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                resumenPunto,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 13, color: context.textoTenue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _pastillaGuardadas(),
      ],
    );
  }

  // --- Pastilla del contador REAL de mediciones guardadas en el punto ---
  // Distinta del "promedio de muestras": empieza en 0, sube 1 por cada
  // medición guardada y se reinicia al cambiar de punto o de terreno.
  Widget _pastillaGuardadas() {
    final verde = colorCategoria('normal', context.brillo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: verde.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.save_outlined, size: 14, color: verde),
          const SizedBox(width: 6),
          Text(
            'Guardadas en este punto: $_guardadasEnPunto',
            style: TextStyle(
              fontSize: 12,
              color: verde,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Tarjeta de una variable medida ---
  Widget _tarjetaMetrica(
    String titulo,
    double? valor,
    String unidad,
    IconData icono,
    Color color, {
    int decimales = 1,
  }) {
    final texto = valor == null ? '—' : valor.toStringAsFixed(decimales);
    return _tarjeta(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icono, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 15,
                color: context.textoFuerte,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: texto,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: context.textoFuerte,
                  ),
                ),
                TextSpan(
                  text: '  $unidad',
                  style: TextStyle(fontSize: 13, color: context.textoTenue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Última línea cruda recibida (depuración) ---
  Widget _lineaCruda() {
    return Row(
      children: [
        Icon(Icons.terminal, size: 14, color: context.textoTenue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _ultimoCrudo.isEmpty ? 'Sin datos recibidos aún' : _ultimoCrudo,
            style: TextStyle(
              fontSize: 11,
              color: context.textoTenue,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // --- Botón para guardar la lectura actual en el historial ---
  Widget _botonGuardar() {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _hayLectura ? _guardarMedicion : null,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Guardar medición'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // --- Banner de condición preliminar (Módulo 3) ---
  // Verde = normal, ámbar = moderado, rojo = crítico. Si es crítico, agrega
  // una alerta preventiva con las variables alteradas. Lenguaje prudente.
  Widget _bannerCondicion() {
    final c = _clasificacion;
    if (c == null) {
      return const SizedBox.shrink(); // sin humedad/CE no clasifica
    }
    final color = colorCategoria(c.categoria, context.brillo);
    final critico = c.categoria == 'crítico';
    final icono = critico
        ? Icons.warning_amber_rounded
        : c.categoria == 'moderado'
        ? Icons.info_outline
        : Icons.check_circle_outline;
    final etiqueta = c.categoria[0].toUpperCase() + c.categoria.substring(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Condición preliminar: $etiqueta',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${c.score.round()}/100',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (critico) ...[
            const SizedBox(height: 10),
            Text(
              c.variablesAlteradas.isEmpty
                  ? 'Alerta preventiva: condición crítica.'
                  : 'Alerta preventiva — ${c.variablesAlteradas.join('  ·  ')}.',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Repite las mediciones y solicita revisión técnica si la '
              'condición persiste.',
              style: TextStyle(color: context.textoFuerte, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Clasificación preliminar; no certifica el terreno.',
            style: TextStyle(
              color: context.textoTenue,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // Contenedor base reutilizable: tarjeta redondeada con borde suave, que se
  // adapta al tema (blanca en claro, superficie elevada en oscuro).
  Widget _tarjeta({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colorTarjeta,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.bordeSuave),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
