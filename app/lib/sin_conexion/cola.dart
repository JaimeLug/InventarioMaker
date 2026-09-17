import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/errores.dart';

/// Lo que se capturó sin señal y espera para enviarse (F-17). Solo en el celular.
class Comando {
  Comando({
    required this.id,
    required this.tipo,
    required this.datos,
    required this.capturado,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.resumen,
    this.articuloIds = const [],
    this.fotos = const [],
    this.porResolver = false,
    this.error,
  });

  /// También es el identificador que evita duplicados en el servidor.
  final String id;

  /// PRESTAMO | DEVOLUCION | CONSUMO | INCIDENCIA | CONTEO | CONTEO_INVENTARIO | APORTE
  final String tipo;
  final Map<String, dynamic> datos;
  final DateTime capturado;
  final String usuarioId;
  final String usuarioNombre;

  /// Cómo se lee en la lista: "Préstamo: Multímetro Truper ×1 a Juan Pérez".
  final String resumen;
  final List<String> articuloIds;
  final List<FotoEnCola> fotos;
  bool porResolver;
  String? error;

  Map<String, dynamic> aMapa() => {
        'id': id,
        'tipo': tipo,
        'datos': datos,
        'capturado': capturado.toUtc().toIso8601String(),
        'usuario_id': usuarioId,
        'usuario_nombre': usuarioNombre,
        'resumen': resumen,
        'articulo_ids': articuloIds,
        'fotos': [for (final f in fotos) f.aMapa()],
        'por_resolver': porResolver,
        'error': error,
      };

  factory Comando.desdeMapa(Map<String, dynamic> m) => Comando(
        id: m['id'] as String,
        tipo: m['tipo'] as String,
        datos: Map<String, dynamic>.from(m['datos'] as Map),
        capturado: DateTime.parse(m['capturado'] as String),
        usuarioId: m['usuario_id'] as String,
        usuarioNombre: m['usuario_nombre'] as String? ?? '',
        resumen: m['resumen'] as String? ?? '',
        articuloIds: [for (final a in (m['articulo_ids'] as List? ?? const [])) a as String],
        fotos: [for (final f in (m['fotos'] as List? ?? const [])) FotoEnCola.desdeMapa(Map<String, dynamic>.from(f as Map))],
        porResolver: m['por_resolver'] as bool? ?? false,
        error: m['error'] as String?,
      );
}

/// Una foto guardada en el celular que se sube antes de mandar su comando. La ruta de destino
/// se decide al capturarla y ya va dentro de los datos del comando.
class FotoEnCola {
  FotoEnCola({required this.archivo, required this.bucket, required this.ruta, this.subida = false});

  final String archivo;
  final String bucket;
  final String ruta;
  bool subida;

  Map<String, dynamic> aMapa() => {'archivo': archivo, 'bucket': bucket, 'ruta': ruta, 'subida': subida};

  factory FotoEnCola.desdeMapa(Map<String, dynamic> m) => FotoEnCola(
      archivo: m['archivo'] as String, bucket: m['bucket'] as String, ruta: m['ruta'] as String, subida: m['subida'] as bool? ?? false);
}

class Enviado {
  const Enviado({required this.resumen, required this.enviado, this.conflicto, this.tarde = false});

  final String resumen;
  final DateTime enviado;
  final String? conflicto;
  final bool tarde;

  Map<String, dynamic> aMapa() => {'resumen': resumen, 'enviado': enviado.toIso8601String(), 'conflicto': conflicto, 'tarde': tarde};

  factory Enviado.desdeMapa(Map<String, dynamic> m) => Enviado(
      resumen: m['resumen'] as String,
      enviado: DateTime.parse(m['enviado'] as String),
      conflicto: m['conflicto'] as String?,
      tarde: m['tarde'] as bool? ?? false);
}

/// La cola, lo guardado para consultar sin señal y el envío automático al volver la conexión.
class ColaSinConexion extends ChangeNotifier {
  ColaSinConexion._(this._dir);

  static ColaSinConexion? _instancia;

  /// null en la web: ahí no se trabaja sin conexión.
  static ColaSinConexion? get instancia => _instancia;

  static const avisoAtraso = Duration(hours: 24);
  static const _cadaCuantoDatos = Duration(minutes: 15);

  final Directory _dir;
  final List<Comando> comandos = [];
  final List<Enviado> enviados = [];
  final Map<String, Object?> _cache = {};
  final Set<String> _bajando = {};

  bool sinSenal = false;
  bool enviando = false;
  bool actualizando = false;
  DateTime? datosDe;

  /// Hay comandos de otra persona o la sesión venció: se envían cuando esa persona entre.
  String? esperandoA;

  /// Diferencia con la hora del servidor, si pasa de 10 minutos.
  Duration? horaMal;

  Timer? _reloj;
  StreamSubscription<List<ConnectivityResult>>? _red;
  StreamSubscription<AuthState>? _sesion;
  Future<void> Function()? _descargar;

  static Future<void> iniciar({required Future<void> Function() descargarDatos}) async {
    if (kIsWeb || _instancia != null) return;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sin_conexion');
    await Directory('${dir.path}/fotos_cola').create(recursive: true);
    await Directory('${dir.path}/miniaturas').create(recursive: true);
    await Directory('${dir.path}/fotos').create(recursive: true);
    final cola = ColaSinConexion._(dir).._descargar = descargarDatos;
    await cola._cargar();
    _instancia = cola;
    cola._escuchar();
  }

  List<Comando> get porEnviar => [for (final c in comandos) if (!c.porResolver) c];
  List<Comando> get porResolver => [for (final c in comandos) if (c.porResolver) c];
  bool get hayAtrasados => porEnviar.any((c) => DateTime.now().difference(c.capturado) > avisoAtraso);

  // --- Archivos --------------------------------------------------------------------

  File _archivo(String nombre) => File('${_dir.path}/$nombre');

  Future<void> _cargar() async {
    try {
      final cola = _archivo('cola.json');
      if (await cola.exists()) {
        comandos.addAll([for (final m in jsonDecode(await cola.readAsString()) as List) Comando.desdeMapa(Map<String, dynamic>.from(m as Map))]);
      }
      final hechos = _archivo('enviados.json');
      if (await hechos.exists()) {
        enviados.addAll([for (final m in jsonDecode(await hechos.readAsString()) as List) Enviado.desdeMapa(Map<String, dynamic>.from(m as Map))]);
      }
      final meta = _archivo('datos_de.txt');
      if (await meta.exists()) datosDe = DateTime.tryParse(await meta.readAsString());
    } on Object catch (e) {
      debugPrint('No se pudo leer la cola: $e');
    }
  }

  Future<void> _guardarCola() async {
    await _archivo('cola.json').writeAsString(jsonEncode([for (final c in comandos) c.aMapa()]), flush: true);
    await _archivo('enviados.json').writeAsString(jsonEncode([for (final e in enviados.take(40)) e.aMapa()]), flush: true);
  }

  /// Copia de lo último que se bajó del servidor (catálogo, contenedores, préstamos…).
  Future<void> guardarCache(String nombre, Object? valor) async {
    _cache[nombre] = valor;
    await _archivo('cache_$nombre.json').writeAsString(jsonEncode(valor), flush: true);
  }

  Object? leerCache(String nombre) {
    if (_cache.containsKey(nombre)) return _cache[nombre];
    final f = _archivo('cache_$nombre.json');
    if (!f.existsSync()) return null;
    try {
      return _cache[nombre] = jsonDecode(f.readAsStringSync());
    } on Object {
      return null;
    }
  }

  List<Map<String, dynamic>>? leerFilas(String nombre) {
    final v = leerCache(nombre);
    return v is List ? [for (final m in v) Map<String, dynamic>.from(m as Map)] : null;
  }

  static String _clave(String ruta) => base64Url.encode(utf8.encode(ruta)).replaceAll('=', '');

  File? miniatura(String ruta) {
    final f = File('${_dir.path}/miniaturas/${_clave(ruta)}.jpg');
    return f.existsSync() ? f : null;
  }

  File? fotoGrande(String ruta) {
    final f = File('${_dir.path}/fotos/${_clave(ruta)}.jpg');
    return f.existsSync() ? f : null;
  }

  /// Guarda una foto que se acaba de ver completa, para abrirla sin señal.
  Future<void> guardarFotoVista(String ruta, String url) async {
    if (fotoGrande(ruta) != null || !_bajando.add(ruta)) return;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) await File('${_dir.path}/fotos/${_clave(ruta)}.jpg').writeAsBytes(r.bodyBytes, flush: true);
    } on Object {
      // Se intentará la próxima vez que se abra.
    } finally {
      _bajando.remove(ruta);
    }
  }

  /// Baja las fotos principales y las guarda reducidas (unos pocos KB cada una).
  Future<void> guardarMiniaturas(Map<String, String> urlsPorRuta) async {
    for (final e in urlsPorRuta.entries) {
      if (miniatura(e.key) != null) continue;
      try {
        final r = await http.get(Uri.parse(e.value)).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) continue;
        final chica = await compute(_reducir, r.bodyBytes);
        if (chica != null) await File('${_dir.path}/miniaturas/${_clave(e.key)}.jpg').writeAsBytes(chica, flush: true);
      } on Object catch (error) {
        if (esFaltaDeConexion(error)) return;
      }
    }
  }

  static Uint8List? _reducir(Uint8List bytes) {
    final imagen = img.decodeImage(bytes);
    if (imagen == null) return null;
    return img.encodeJpg(img.copyResize(imagen, width: imagen.width >= imagen.height ? 240 : null, height: imagen.width < imagen.height ? 240 : null), quality: 70);
  }

  // --- Cola --------------------------------------------------------------------------

  /// Guarda el comando y sus fotos (bytes con la ruta que tendrán en el servidor).
  Future<void> agregar(Comando c, {Map<String, ({Uint8List bytes, String bucket})> fotos = const {}}) async {
    final guardadas = <FotoEnCola>[];
    for (final e in fotos.entries) {
      final nombre = '${c.id}_${guardadas.length}.jpg';
      await File('${_dir.path}/fotos_cola/$nombre').writeAsBytes(e.value.bytes, flush: true);
      guardadas.add(FotoEnCola(archivo: nombre, bucket: e.value.bucket, ruta: e.key));
    }
    comandos.add(Comando(
      id: c.id,
      tipo: c.tipo,
      datos: c.datos,
      capturado: c.capturado,
      usuarioId: c.usuarioId,
      usuarioNombre: c.usuarioNombre,
      resumen: c.resumen,
      articuloIds: c.articuloIds,
      fotos: guardadas,
    ));
    sinSenal = true;
    await _guardarCola();
    notifyListeners();
  }

  /// Quita un comando que todavía no se envía (por ejemplo, "Deshacer" un préstamo sin señal).
  Future<bool> quitar(String id) async {
    final c = comandos.where((x) => x.id == id).firstOrNull;
    if (c == null) return false;
    comandos.remove(c);
    for (final f in c.fotos) {
      final archivo = File('${_dir.path}/fotos_cola/${f.archivo}');
      if (await archivo.exists()) await archivo.delete();
    }
    await _guardarCola();
    notifyListeners();
    return true;
  }

  Future<void> reintentar(String id) async {
    final c = comandos.where((x) => x.id == id).firstOrNull;
    if (c == null) return;
    c
      ..porResolver = false
      ..error = null;
    await _guardarCola();
    notifyListeners();
    unawaited(enviar());
  }

  /// Manda en orden lo que haya. Se detiene si no hay señal o si falta que entre la persona que lo capturó.
  Future<void> enviar() async {
    if (enviando || porEnviar.isEmpty) return;
    enviando = true;
    notifyListeners();
    final cliente = Supabase.instance.client;
    try {
      esperandoA = null;
      for (final c in porEnviar) {
        if (cliente.auth.currentUser?.id != c.usuarioId) {
          esperandoA = c.usuarioNombre;
          break;
        }
        try {
          for (final f in c.fotos.where((f) => !f.subida)) {
            final bytes = await File('${_dir.path}/fotos_cola/${f.archivo}').readAsBytes();
            try {
              await cliente.storage.from(f.bucket).uploadBinary(f.ruta, bytes,
                  fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
            } on StorageException catch (e) {
              // Ya se había subido en un intento anterior que perdió la respuesta.
              if (!(e.statusCode == '409' || e.message.toLowerCase().contains('exist'))) rethrow;
            }
            f.subida = true;
            await _guardarCola();
          }
          final r = await cliente.rpc('comando_sin_conexion', params: {
            'p_id': c.id,
            'p_tipo': c.tipo,
            'p_datos': c.datos,
            'p_fecha_dispositivo': c.capturado.toUtc().toIso8601String(),
          }).timeout(const Duration(seconds: 40));
          final m = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
          comandos.remove(c);
          for (final f in c.fotos) {
            final archivo = File('${_dir.path}/fotos_cola/${f.archivo}');
            if (await archivo.exists()) await archivo.delete();
          }
          enviados.insert(0, Enviado(resumen: c.resumen, enviado: DateTime.now(), conflicto: m['conflicto'] as String?, tarde: m['tarde'] == true));
          sinSenal = false;
          _revisarHora(m['hora_servidor']);
          await _guardarCola();
          notifyListeners();
        } on Object catch (e) {
          if (esFaltaDeConexion(e)) {
            sinSenal = true;
            break;
          }
          final error = traducir(e);
          if (error.pideAcceso || error.codigo == '42501' || error.detalle == 'SESION_VENCIDA' || error.detalle == 'SIN_SESION') {
            esperandoA = c.usuarioNombre;
            break;
          }
          c
            ..porResolver = true
            ..error = error.mensaje;
          await _guardarCola();
          notifyListeners();
        }
      }
    } finally {
      enviando = false;
      notifyListeners();
    }
  }

  void _revisarHora(Object? servidor) {
    final hora = servidor == null ? null : DateTime.tryParse('$servidor');
    if (hora == null) return;
    final diferencia = DateTime.now().difference(hora);
    horaMal = diferencia.abs() > const Duration(minutes: 10) ? diferencia : null;
  }

  /// Baja otra vez lo necesario para trabajar sin señal.
  Future<void> actualizarDatos() async {
    if (actualizando || _descargar == null) return;
    actualizando = true;
    notifyListeners();
    try {
      await _descargar!();
      datosDe = DateTime.now();
      sinSenal = false;
      await _archivo('datos_de.txt').writeAsString(datosDe!.toIso8601String());
      try {
        _revisarHora(await Supabase.instance.client.rpc('hora_servidor'));
      } on Object {
        // No es grave.
      }
    } on Object catch (e) {
      if (esFaltaDeConexion(e)) sinSenal = true;
    } finally {
      actualizando = false;
      notifyListeners();
    }
  }

  void _escuchar() {
    _red = Connectivity().onConnectivityChanged.listen((estado) {
      if (estado.every((r) => r == ConnectivityResult.none)) {
        sinSenal = true;
        notifyListeners();
      } else {
        unawaited(_alVolver());
      }
    });
    _sesion = Supabase.instance.client.auth.onAuthStateChange.listen((cambio) {
      if (cambio.session != null && porEnviar.isNotEmpty) unawaited(enviar());
    });
    _reloj = Timer.periodic(const Duration(minutes: 1), (_) {
      if (porEnviar.isNotEmpty) unawaited(enviar());
      if (datosDe == null || DateTime.now().difference(datosDe!) > _cadaCuantoDatos) unawaited(actualizarDatos());
    });
    unawaited(_alVolver());
  }

  /// Al abrir la app o recuperar la señal: primero se envía lo pendiente y luego se bajan datos frescos.
  Future<void> _alVolver() async {
    await enviar();
    await actualizarDatos();
  }

  Future<void> alReanudar() => _alVolver();

  @override
  void dispose() {
    _reloj?.cancel();
    _red?.cancel();
    _sesion?.cancel();
    super.dispose();
  }
}
