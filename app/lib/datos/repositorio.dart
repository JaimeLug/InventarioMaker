import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../acceso/sesion.dart';
import '../configuracion.dart';
import '../modelos/articulo.dart';
import '../modelos/catalogos.dart';
import '../modelos/contenedores.dart';
import '../modelos/movimientos.dart';
import '../modelos/otros.dart';
import '../modelos/pendientes.dart';
import '../modelos/solicitudes.dart';
import '../sin_conexion/cola.dart';
import 'errores.dart';

final repositorioProvider = Provider<Repositorio>((ref) => Repositorio(Supabase.instance.client));

/// Una foto elegida en el formulario. Se sube al guardar; si la subida ya ocurrió
/// (por ejemplo, antes de un error), no se vuelve a subir.
class FotoNueva {
  FotoNueva(this.bytes, {this.tipo = TipoFoto.general});

  final Uint8List bytes;
  TipoFoto tipo;
  String? rutaSubida;
}

/// Todo el acceso a Supabase pasa por aquí.
class Repositorio {
  Repositorio(this._c);

  final SupabaseClient _c;
  static const _uuid = Uuid();

  // --- Consulta (abierta, sin sesión) ------------------------------------------
  Future<List<Articulo>> articulos() async {
    final filas = await _guardadas('articulos', () => _c
        .from('v_inventario')
        .select()
        .eq('activo', true)
        // En el cliente de Dart, order() es descendente si no se indica.
        .order('categoria', ascending: true)
        .order('ref_foto', ascending: true, nullsFirst: false)
        .order('nombre', ascending: true));
    return filas.map(Articulo.desdeMapa).toList();
  }

  Future<Articulo?> articulo(String id) async {
    try {
      final fila = await _c.from('v_inventario').select().eq('id', id).maybeSingle();
      return fila == null ? null : Articulo.desdeMapa(fila);
    } on Object catch (e) {
      final copia = _deCopia(e, 'articulos');
      if (copia == null) rethrow;
      final m = copia.where((m) => m['id'] == id).firstOrNull;
      return m == null ? null : Articulo.desdeMapa(m);
    }
  }

  Future<String?> idPorCodigo(String codigo) async {
    try {
      final fila = await _c.from('v_inventario').select('id').eq('codigo', codigo.toUpperCase()).maybeSingle();
      return fila?['id'] as String?;
    } on Object catch (e) {
      final copia = _deCopia(e, 'articulos');
      if (copia == null) rethrow;
      return copia.where((m) => m['codigo'] == codigo.toUpperCase()).firstOrNull?['id'] as String?;
    }
  }

  Future<List<Foto>> fotos(String articuloId) async {
    final filas = await _guardadas('fotos_$articuloId', () => _c
        .from('foto')
        .select('id, url, es_principal, tipo, tomada_en')
        .eq('articulo_id', articuloId)
        .order('es_principal', ascending: false)
        .order('tomada_en', ascending: false));
    return filas
        .map((m) => Foto(
              id: m['id'] as String,
              ruta: m['url'] as String,
              url: urlFoto(m['url'] as String),
              esPrincipal: m['es_principal'] as bool,
              tipo: TipoFoto.desde(m['tipo'] as String),
              tomadaEn: DateTime.parse(m['tomada_en'] as String),
            ))
        .toList();
  }

  Future<List<MovimientoPublico>> historial(String articuloId) async {
    final filas = await _guardadas('historial_$articuloId', () => _c
        .from('v_historial_publico')
        .select()
        .eq('articulo_id', articuloId)
        .order('fecha', ascending: false)
        .limit(100));
    return filas.map(MovimientoPublico.desdeMapa).toList();
  }

  Future<List<Pendiente>> pendientes(String articuloId) async {
    final filas = await _guardadas('pendientes_$articuloId', () => _c
        .from('tarea_pendiente')
        .select('tipo, descripcion, prioridad')
        .eq('articulo_id', articuloId)
        .eq('resuelta', false)
        .order('prioridad', ascending: false));
    return filas.map(Pendiente.desdeMapa).toList();
  }

  String urlFoto(String ruta) => _c.storage.from(Configuracion.almacenFotos).getPublicUrl(ruta);

  // --- Sesión -------------------------------------------------------------------
  bool get hayToken => _c.auth.currentSession != null;

  Future<Sesion?> miSesion() async {
    if (!hayToken) return null;
    try {
      final r = await _c.rpc('mi_sesion');
      final m = r == null ? null : Map<String, dynamic>.from(r as Map);
      if (m != null) await _cola?.guardarCache('sesion', m);
      return Sesion.desdeMapa(m);
    } on Object catch (e) {
      // Sin señal se sigue con la última sesión de esta misma cuenta; el servidor la revisa otra vez al enviar.
      final copia = _cola?.leerCache('sesion');
      if (_cola == null || !esFaltaDeConexion(e) || copia is! Map || copia['id'] != _c.auth.currentUser?.id) rethrow;
      return Sesion.desdeMapa(Map<String, dynamic>.from(copia));
    }
  }

  Future<List<PersonaPin>> personasConPin() async {
    final filas = await _guardadas('personas_pin', () => _c.rpc('pin_usuarios'));
    return filas.map((m) => PersonaPin(m['id'] as String, m['nombre'] as String)).toList();
  }

  Future<void> entrarConPin(String usuarioId, String pin) async {
    final r = await _c.functions.invoke('acceso-pin', body: {'usuario_id': usuarioId, 'pin': pin});
    final datos = Map<String, dynamic>.from(r.data as Map);
    if (datos['ok'] != true) throw ErrorApp(datos['mensaje'] as String? ?? 'No se pudo entrar.');
    await _c.auth.setSession(datos['refresh_token'] as String);
  }

  Future<void> entrarConContrasena(String correo, String contrasena) async {
    await _c.auth.signInWithPassword(email: correo.trim().toLowerCase(), password: contrasena);
  }

  /// Devuelve null si quedó confirmada, o el mensaje de por qué no.
  Future<String?> confirmarContrasena(String contrasena) async {
    final r = Map<String, dynamic>.from(await _c.rpc('confirmar_contrasena', params: {'p_contrasena': contrasena}) as Map);
    return r['ok'] == true ? null : r['mensaje'] as String;
  }

  /// Cambiar la contraseña de quien entró: primero se revisa la actual, luego se guarda la nueva.
  Future<void> cambiarMiContrasena(String actual, String nueva) async {
    final problema = await confirmarContrasena(actual);
    if (problema != null) throw ErrorApp(problema);
    await _c.auth.updateUser(UserAttributes(password: nueva));
  }

  Future<void> salir() => _c.auth.signOut();

  Future<void> establecerPin(String usuarioId, String pin) =>
      _c.rpc('pin_establecer', params: {'p_usuario': usuarioId, 'p_pin': pin});

  // --- Artículos --------------------------------------------------------------------
  Future<String> subirFoto(String articuloId, FotoNueva foto) async {
    if (foto.rutaSubida != null) return foto.rutaSubida!;
    final ruta = 'articulos/$articuloId/${DateTime.now().toUtc().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    await _c.storage.from(Configuracion.almacenFotos).uploadBinary(
          ruta,
          foto.bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
    return foto.rutaSubida = ruta;
  }

  /// Alta (F-11). [id] y [comando] los genera el formulario una sola vez, para que reintentar no duplique.
  Future<String> crearArticulo({
    required String id,
    required String comando,
    required Map<String, dynamic> datos,
    required int? cantidad,
    required List<FotoNueva> fotos,
  }) async {
    final rutas = <Map<String, String>>[];
    for (final f in fotos) {
      rutas.add({'ruta': await subirFoto(id, f), 'tipo': f.tipo.codigo});
    }
    final r = await _c.rpc('articulo_crear', params: {
      'p_id': id,
      'p_datos': datos,
      'p_cantidad': cantidad,
      'p_fotos': rutas,
      'p_comando': comando,
    });
    return (r as Map)['codigo'] as String;
  }

  Future<void> editarArticulo(String id, Map<String, dynamic> cambios, {String? justificacion}) =>
      _c.rpc('articulo_editar', params: {'p_id': id, 'p_cambios': cambios, 'p_justificacion': justificacion});

  Future<void> agregarFoto(String articuloId, FotoNueva foto, {bool principal = false}) async {
    final ruta = await subirFoto(articuloId, foto);
    await _c.rpc('foto_agregar', params: {
      'p_articulo': articuloId,
      'p_ruta': ruta,
      'p_tipo': foto.tipo.codigo,
      'p_principal': principal,
    });
  }

  Future<void> hacerPrincipal(String fotoId) => _c.rpc('foto_hacer_principal', params: {'p_foto': fotoId});

  // --- Cuentas ----------------------------------------------------------------------
  Future<List<Cuenta>> cuentas() async {
    final filas = await _c.rpc('cuentas_listar') as List<dynamic>;
    return filas.map((m) => Cuenta.desdeMapa(Map<String, dynamic>.from(m as Map))).toList();
  }

  /// CREAR, DESACTIVAR, REACTIVAR o CONTRASENA, por la función del servidor "cuentas".
  Future<void> administrarCuenta(Map<String, dynamic> solicitud) async {
    final r = await _c.functions.invoke('cuentas', body: solicitud);
    final datos = Map<String, dynamic>.from(r.data as Map);
    if (datos['ok'] != true) {
      throw ErrorApp(datos['mensaje'] as String? ?? 'No se pudo completar.',
          codigo: datos['codigo'] as String?, detalle: datos['detalle'] as String?);
    }
  }

  // --- Movimientos (Fase 3) ------------------------------------------------------------
  List<Map<String, dynamic>> _filas(Object? r) => [for (final m in (r as List)) Map<String, dynamic>.from(m as Map)];

  Future<int> vencidosContar() async => await _c.rpc('vencidos_contar') as int;

  Future<int> porRevisarContar() async => await _c.rpc('por_revisar_contar') as int;

  /// F-07. Devuelve el grupo del préstamo (para deshacer). Sin señal queda en la cola y el grupo es [comando].
  Future<String> prestar({
    required List<({String articuloId, int cantidad})> lineas,
    required String comando,
    String? responsableUsuario,
    String? responsableSolicitante,
    DateTime? fechaCompromiso,
    String? nota,
  }) async {
    String? grupo;
    await _oEnCola(() async {
      final r = await _c.rpc('prestamo_registrar', params: {
        'p_lineas': [for (final l in lineas) {'articulo_id': l.articuloId, 'cantidad': l.cantidad}],
        'p_responsable_usuario': responsableUsuario,
        'p_responsable_solicitante': responsableSolicitante,
        'p_fecha_compromiso': fechaCompromiso?.toUtc().toIso8601String(),
        'p_nota': nota,
        'p_comando': comando,
      });
      grupo = (r as Map)['grupo'] as String;
    }, () => _comando(
          comando,
          'PRESTAMO',
          {
            'lineas': [for (final l in lineas) {'articulo_id': l.articuloId, 'cantidad': l.cantidad}],
            'responsable_usuario': responsableUsuario,
            'responsable_solicitante': responsableSolicitante,
            'fecha_compromiso': (fechaCompromiso ?? _finJornada()).toUtc().toIso8601String(),
            'nota': nota,
          },
          'Préstamo: ${_nombres(lineas)}${responsableSolicitante == null ? '' : ' a ${_nombreSolicitante(responsableSolicitante)}'}',
          [for (final l in lineas) l.articuloId],
          estimar: {for (final l in lineas) l.articuloId: (existencia: 0, prestado: l.cantidad)},
        ));
    return grupo ?? comando;
  }

  /// Si el préstamo sigue en la cola (sin señal), basta con quitarlo de ahí.
  Future<void> deshacerPrestamo(String grupo) async {
    final c = _cola?.comandos.where((x) => x.id == grupo && !x.porResolver).firstOrNull;
    if (c == null) {
      await _c.rpc('prestamo_deshacer', params: {'p_grupo': grupo});
      return;
    }
    for (final l in (c.datos['lineas'] as List)) {
      await _estimar((l as Map)['articulo_id'] as String, existencia: 0, prestado: -(l['cantidad'] as int));
    }
    await _cola!.quitar(grupo);
  }

  Future<void> extenderPrestamo(String prestamoId, DateTime fecha, String motivo) => _c.rpc('prestamo_extender',
      params: {'p_prestamo': prestamoId, 'p_fecha': fecha.toUtc().toIso8601String(), 'p_motivo': motivo});


  /// Identificador de un préstamo que todavía está en la cola: el mismo que el servidor
  /// le pone al aplicarlo (movimiento.comando_id = md5 del comando + el artículo), para
  /// poder devolverlo aunque no haya señal.
  static String idDePrestamoEnCola(String comando, String articuloId) {
    final h = md5.convert(utf8.encode('$comando$articuloId')).toString();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<List<PrestamoAbierto>> prestamosDeArticulo(String articuloId) async {
    try {
      return _filas(await _c.rpc('prestamos_de_articulo', params: {'p_articulo': articuloId})).map(PrestamoAbierto.desdeMapa).toList();
    } on Object catch (e) {
      final copia = _deCopia(e, 'prestamos');
      if (copia == null) rethrow;
      // Lo que ya se recibió sin señal y sigue en la cola no se vuelve a ofrecer.
      final recibido = <String, int>{};
      for (final c in _cola!.comandos.where((c) => c.tipo == 'DEVOLUCION')) {
        for (final l in (c.datos['lineas'] as List)) {
          final m = l as Map;
          final cierra = m['faltante'] == 'PERDIDO' ? 1 << 30 : (m['regresan'] as int? ?? 0);
          recibido[m['prestamo_id'] as String] = (recibido[m['prestamo_id']] ?? 0) + cierra;
        }
      }
      final lista = [
        for (final m in copia.where((m) => m['articulo_id'] == articuloId))
          if ((m['pendiente'] as int) - (recibido[m['prestamo_id']] ?? 0) > 0)
            PrestamoAbierto.desdeMapa({...m, 'pendiente': (m['pendiente'] as int) - (recibido[m['prestamo_id']] ?? 0)}),
      ];
      // Lo que se prestó sin señal y sigue en la cola también se puede devolver.
      for (final c in _cola!.comandos.where((c) => c.tipo == 'PRESTAMO' && !c.porResolver)) {
        for (final l in (c.datos['lineas'] as List)) {
          final m = l as Map;
          if (m['articulo_id'] != articuloId) continue;
          final id = idDePrestamoEnCola(c.id, articuloId);
          final pendiente = (m['cantidad'] as int) - (recibido[id] ?? 0);
          if (pendiente <= 0) continue;
          final solicitante = c.datos['responsable_solicitante'] as String?;
          lista.add(PrestamoAbierto.desdeMapa({
            'prestamo_id': id,
            'cantidad': m['cantidad'],
            'pendiente': pendiente,
            'fecha': c.capturado.toUtc().toIso8601String(),
            'vence_en': c.datos['fecha_compromiso'],
            'vencido': false,
            'a_cargo': solicitante == null ? c.usuarioNombre : _nombreSolicitante(solicitante),
            'autorizo': c.usuarioNombre,
          }));
        }
      }
      return lista;
    }
  }

  Future<List<PrestamoListado>> misPrestamos() async => _filas(await _c.rpc('mis_prestamos')).map(PrestamoListado.desdeMapa).toList();

  Future<List<PrestamoListado>> prestamosAbiertos() async =>
      _filas(await _c.rpc('prestamos_abiertos_listar')).map(PrestamoListado.desdeMapa).toList();

  /// Por nombre, solo entre quienes ya pidieron o ya recibieron material (Fase 10).
  /// A alguien nuevo se le sigue buscando por matrícula exacta. Necesita señal.
  Future<List<SolicitanteEncontrado>> buscarSolicitantePorNombre(String texto) async =>
      _filas(await _c.rpc('solicitante_buscar_conocido', params: {'p_texto': texto}))
          .map(SolicitanteEncontrado.desdeMapa)
          .toList();

  Future<List<SolicitanteEncontrado>> buscarSolicitante(String matricula) async {
    try {
      return _filas(await _c.rpc('solicitante_buscar', params: {'p_matricula': matricula})).map(SolicitanteEncontrado.desdeMapa).toList();
    } on Object catch (e) {
      // Sin señal: solo quienes ya pidieron antes, y también por matrícula exacta.
      final copia = _deCopia(e, 'solicitantes');
      if (copia == null) rethrow;
      final buscada = matricula.trim().toLowerCase();
      return [
        for (final m in copia)
          if ('${m['matricula']}'.trim().toLowerCase() == buscada) SolicitanteEncontrado.desdeMapa({...m, 'verificada': false, 'vencidos': 0}),
      ];
    }
  }

  Future<String> crearSolicitante({
    required String nombre,
    required TipoSolicitante tipo,
    required String matricula,
    required String grupo,
    required String correo,
    String? telefono,
  }) async =>
      await _c.rpc('solicitante_crear_rapido', params: {
        'p_nombre': nombre,
        'p_tipo': tipo.codigo,
        'p_matricula': matricula,
        'p_grupo': grupo,
        'p_correo': correo,
        'p_telefono': telefono,
      }) as String;

  /// Foto al almacén privado, en carpeta/ID (incidencias, entregas o identificaciones).
  Future<String> subirPrivada(String carpeta, String id, FotoNueva f) async {
    if (f.rutaSubida != null) return f.rutaSubida!;
    final ruta = '$carpeta/$id/${DateTime.now().toUtc().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    await _c.storage.from('privado').uploadBinary(ruta, f.bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    return f.rutaSubida = ruta;
  }

  /// Fotos de daños y pérdidas: almacén privado, en la carpeta incidencias/ID del reporte.
  Future<List<Map<String, String>>> subirFotosPrivadas(String incidenciaId, List<FotoNueva> fotos) async =>
      [for (final f in fotos) {'ruta': await subirPrivada('incidencias', incidenciaId, f)}];

  /// Enlace temporal (5 minutos) a una foto privada. Solo funciona para quien tiene permiso.
  Future<String> urlPrivada(String ruta) => _c.storage.from('privado').createSignedUrl(ruta, 300);

  /// F-08. Una línea por préstamo.
  Future<void> devolver({
    required String comando,
    required String prestamoId,
    required int regresan,
    int danadas = 0,
    String? incidenciaDanoId,
    String? notaDano,
    List<FotoNueva> fotosDano = const [],
    bool faltantePerdido = false,
    String? incidenciaPerdidaId,
    String? notaPerdida,
    List<FotoNueva> fotosPerdida = const [],
    String? sinFotoPerdida,
  }) async {
    Future<Map<String, dynamic>> linea(Future<List<Map<String, String>>> Function(String incidencia, List<FotoNueva> fotos) fotos) async {
      final l = <String, dynamic>{'prestamo_id': prestamoId, 'regresan': regresan, 'danadas': danadas};
      if (danadas > 0) {
        l.addAll({'incidencia_dano_id': incidenciaDanoId, 'nota_dano': notaDano, 'fotos_dano': await fotos(incidenciaDanoId!, fotosDano)});
      }
      if (faltantePerdido) {
        l.addAll({
          'faltante': 'PERDIDO',
          'incidencia_perdida_id': incidenciaPerdidaId,
          'nota_perdida': notaPerdida,
          'fotos_perdida': await fotos(incidenciaPerdidaId!, fotosPerdida),
          'sin_foto_perdida': sinFotoPerdida,
        });
      }
      return l;
    }

    await _oEnCola(() async {
      await _c.rpc('devolucion_registrar', params: {'p_lineas': [await linea(subirFotosPrivadas)], 'p_comando': comando});
    }, () async {
      final guardadas = <String, ({Uint8List bytes, String bucket})>{};
      final l = await linea((incidencia, fotos) async => [
            for (final f in fotos) {'ruta': _guardarFotoPrivada(guardadas, incidencia, f)},
          ]);
      final articulo = _cola?.leerFilas('prestamos')?.where((m) => m['prestamo_id'] == prestamoId).firstOrNull?['articulo_id'] as String?;
      return _comando(
        comando,
        'DEVOLUCION',
        {'lineas': [l]},
        'Devolución: ${articulo == null ? 'préstamo' : _nombreArticulo(articulo)} ×$regresan${danadas > 0 ? ' ($danadas con daño)' : ''}',
        [?articulo],
        fotos: guardadas,
        estimar: {if (articulo != null) articulo: (existencia: 0, prestado: -regresan)},
      );
    });
  }

  /// F-09. [id] lo genera la pantalla una vez: reintentar no duplica.
  Future<void> reportar({
    required String id,
    required String articuloId,
    required String tipo,
    required int cantidad,
    required String nota,
    required List<FotoNueva> fotos,
    String? prestamoId,
    String? sinFoto,
  }) async {
    await _oEnCola(() async {
      await _c.rpc('incidencia_reportar', params: {
        'p_id': id,
        'p_articulo': articuloId,
        'p_tipo': tipo,
        'p_cantidad': cantidad,
        'p_prestamo': prestamoId,
        'p_nota': nota,
        'p_fotos': await subirFotosPrivadas(id, fotos),
        'p_sin_foto': sinFoto,
      });
    }, () {
      final guardadas = <String, ({Uint8List bytes, String bucket})>{};
      final rutas = [for (final f in fotos) {'ruta': _guardarFotoPrivada(guardadas, id, f)}];
      return _comando(
        id,
        'INCIDENCIA',
        {'articulo_id': articuloId, 'tipo': tipo, 'cantidad': cantidad, 'prestamo_id': prestamoId, 'nota': nota, 'fotos': rutas, 'sin_foto': sinFoto},
        '${tipo == 'DANO' ? 'Daño' : 'Pérdida'}: ${_nombreArticulo(articuloId)} ×$cantidad',
        [articuloId],
        fotos: guardadas,
      );
    });
  }

  /// F-10. Devuelve true si se aplicó; false si quedó por autorizar.
  Future<bool> registrarUso(String articuloId, int cantidad, String? nota, String comando) async {
    var aplicado = false;
    await _oEnCola(() async {
      final r = await _c.rpc('consumo_registrar',
          params: {'p_articulo': articuloId, 'p_cantidad': cantidad, 'p_nota': nota, 'p_comando': comando});
      aplicado = (r as Map)['aplicado'] as bool;
    }, () => _comando(comando, 'CONSUMO', {'articulo_id': articuloId, 'cantidad': cantidad, 'nota': nota},
        'Uso: ${_nombreArticulo(articuloId)} ×$cantidad', [articuloId]));
    return aplicado;
  }

  Future<List<Incidencia>> porRevisar() async => _filas(await _c.rpc('por_revisar')).map(Incidencia.desdeMapa).toList();

  Future<List<Incidencia>> misReportes() async => _filas(await _c.rpc('mis_reportes')).map(Incidencia.desdeMapa).toList();

  Future<void> resolverIncidencias(List<String> ids, {required bool confirmar, String? motivo}) => _c.rpc('incidencia_resolver',
      params: {'p_ids': ids, 'p_decision': confirmar ? 'CONFIRMAR' : 'DESCARTAR', 'p_motivo': motivo});

  Future<void> comentarIncidencia(String id, String texto) =>
      _c.rpc('incidencia_comentar', params: {'p_incidencia': id, 'p_texto': texto});

  Future<void> reparar(String articuloId, int cantidad, String? nota) =>
      _c.rpc('reparacion_registrar', params: {'p_articulo': articuloId, 'p_cantidad': cantidad, 'p_nota': nota});

  Future<({int diferencia, EstadoInventario estado})> ajustarConteo(
      String articuloId, int enTaller, String motivo, String? nota) async {
    final r = Map<String, dynamic>.from(await _c.rpc('ajuste_conteo',
        params: {'p_articulo': articuloId, 'p_en_taller': enTaller, 'p_motivo': motivo, 'p_nota': nota}) as Map);
    return (diferencia: r['diferencia'] as int, estado: EstadoInventario.desde(r['estado'] as String));
  }

  /// [cantidad] null = baja total. Devuelve si la baja quedó "en trámite" (resguardo sin oficio).
  Future<bool> darDeBaja(String articuloId,
      {int? cantidad,
      bool deFueraDeServicio = false,
      required String motivo,
      required String justificacion,
      String? oficio}) async {
    final r = await _c.rpc('baja_registrar', params: {
      'p_articulo': articuloId,
      'p_cantidad': cantidad,
      'p_de_fuera_de_servicio': deFueraDeServicio,
      'p_motivo': motivo,
      'p_justificacion': justificacion,
      'p_oficio': oficio,
    });
    return (r as Map)['en_tramite'] as bool;
  }

  Future<void> marcarPrestable(String articuloId, bool prestable, String? motivo) =>
      _c.rpc('articulo_marcar_prestable', params: {'p_articulo': articuloId, 'p_prestable': prestable, 'p_motivo': motivo});

  Future<void> registrarOficioBaja(String articuloId, String oficio) =>
      _c.rpc('baja_registrar_oficio', params: {'p_articulo': articuloId, 'p_oficio': oficio});

  Future<void> reactivar(String articuloId, int cantidad, String justificacion) => _c.rpc('articulo_reactivar',
      params: {'p_articulo': articuloId, 'p_cantidad': cantidad, 'p_justificacion': justificacion});

  Future<List<MovimientoDetallado>> historialConNombres(String articuloId) async =>
      _filas(await _c.rpc('historial_articulo', params: {'p_articulo': articuloId})).map(MovimientoDetallado.desdeMapa).toList();

  Future<List<EventoBitacora>> bitacora({int? antes}) async =>
      _filas(await _c.rpc('bitacora_listar', params: {'p_antes': antes, 'p_limite': 100})).map(EventoBitacora.desdeMapa).toList();

  // --- Solicitudes sin cuenta (Fase 3b) ---------------------------------------------------
  Map<String, dynamic> _mapa(Object? r) => Map<String, dynamic>.from(r as Map);

  /// Por la función del servidor "solicitud-publica" (agrega la red para el freno contra abusos).
  Future<SolicitudEnviada> enviarSolicitud(Map<String, dynamic> datos, String dispositivo) async {
    final r = await _c.functions.invoke('solicitud-publica', body: {'accion': 'enviar', 'datos': datos, 'dispositivo': dispositivo});
    final m = _mapa(r.data);
    if (m['ok'] != true) throw ErrorApp(m['mensaje'] as String? ?? 'No se pudo enviar la solicitud.');
    return SolicitudEnviada.desdeMapa(m);
  }

  Future<String> recuperarEnlace(String folio, String matricula, String dispositivo) async {
    final r = await _c.functions
        .invoke('solicitud-publica', body: {'accion': 'recuperar', 'folio': folio, 'matricula': matricula, 'dispositivo': dispositivo});
    final m = _mapa(r.data);
    if (m['ok'] != true) throw ErrorApp(m['mensaje'] as String? ?? 'No se pudo completar.');
    return m['mensaje'] as String;
  }

  Future<SolicitudPublica?> solicitudPublica(String token) async {
    final r = await _c.rpc('solicitud_publica_estado', params: {'p_token': token});
    return r == null ? null : SolicitudPublica.desdeMapa(_mapa(r));
  }

  Future<SolicitudPublica> confirmarSolicitud(String token) async =>
      SolicitudPublica.desdeMapa(_mapa(await _c.rpc('solicitud_publica_confirmar', params: {'p_token': token})));

  Future<SolicitudPublica> cancelarSolicitudPublica(String token) async =>
      SolicitudPublica.desdeMapa(_mapa(await _c.rpc('solicitud_publica_cancelar', params: {'p_token': token})));

  Future<SolicitudPublica> noFuiYo(String token) async =>
      SolicitudPublica.desdeMapa(_mapa(await _c.rpc('solicitud_publica_no_fui_yo', params: {'p_token': token})));

  /// Devuelve null si se aceptó, o el mensaje de por qué no.
  Future<String?> canjearCodigo(String token, String codigo) async {
    final m = _mapa(await _c.rpc('solicitud_publica_canjear', params: {'p_token': token, 'p_codigo': codigo}));
    return m['ok'] == true ? null : m['mensaje'] as String;
  }

  // --- Bandeja y entrega (responsable y sub administración) ------------------------------
  Future<({int porRevisar, int porEntregar, int sinConfirmar})> solicitudesContar() async {
    final m = _mapa(await _c.rpc('solicitudes_contar'));
    return (porRevisar: m['por_revisar'] as int, porEntregar: m['por_entregar'] as int, sinConfirmar: m['sin_confirmar'] as int);
  }

  Future<List<SolicitudResumen>> solicitudes(String grupo) async =>
      _filas(await _c.rpc('solicitudes_listar', params: {'p_grupo': grupo})).map(SolicitudResumen.desdeMapa).toList();

  Future<SolicitudDetalle> solicitudDetalle(String id) async =>
      SolicitudDetalle.desdeMapa(_mapa(await _c.rpc('solicitud_detalle', params: {'p_id': id})));

  Future<void> aprobarSolicitud(String id,
          {required Map<String, int> cantidades, DateTime? fecha, String? nota, required String vigencia}) =>
      _c.rpc('solicitud_aprobar', params: {
        'p_id': id,
        'p_lineas': [for (final e in cantidades.entries) {'articulo_id': e.key, 'cantidad': e.value}],
        'p_fecha': fecha?.toUtc().toIso8601String(),
        'p_nota': nota,
        'p_vigencia': vigencia,
      });

  Future<void> rechazarSolicitud(String id, String motivo, String? detalle) =>
      _c.rpc('solicitud_rechazar', params: {'p_id': id, 'p_motivo': motivo, 'p_detalle': detalle});

  Future<void> cancelarSolicitud(String id, String motivo) => _c.rpc('solicitud_cancelar', params: {'p_id': id, 'p_motivo': motivo});

  Future<void> confirmarEnPersona(String id) => _c.rpc('solicitud_confirmar_en_persona', params: {'p_id': id});

  Future<void> codigoNuevo(String id, String vigencia) => _c.rpc('solicitud_codigo_nuevo', params: {'p_id': id, 'p_vigencia': vigencia});

  /// Devuelve null si se aceptó, o el mensaje de por qué no.
  Future<String?> canjearEnLaboratorio(String id, String matricula, String codigo) async {
    final m = _mapa(await _c.rpc('solicitud_canjear_en_laboratorio', params: {'p_id': id, 'p_matricula': matricula, 'p_codigo': codigo}));
    return m['ok'] == true ? null : m['mensaje'] as String;
  }

  Future<void> entregarSolicitud(String id,
      {required String tipoIdentificacion,
      required FotoNueva identificacion,
      required List<FotoNueva> material,
      DateTime? fechaDevolucion}) async {
    final ident = await subirPrivada('identificaciones', id, identificacion);
    final fotos = [for (final f in material) {'ruta': await subirPrivada('entregas', id, f)}];
    await _c.rpc('solicitud_entregar', params: {
      'p_id': id,
      'p_tipo_identificacion': tipoIdentificacion,
      'p_foto_identificacion': ident,
      'p_fotos_material': fotos,
      'p_fecha_devolucion': fechaDevolucion?.toUtc().toIso8601String(),
    });
  }

  Future<void> anularEntrega(String id, String motivo) => _c.rpc('solicitud_entrega_anular', params: {'p_id': id, 'p_motivo': motivo});

  /// Deja el registro en la bitácora y devuelve enlaces temporales (5 minutos) a la identificación.
  Future<List<String>> verIdentificacion(String solicitudId) async {
    final rutas = [for (final r in (await _c.rpc('identificacion_ver', params: {'p_solicitud': solicitudId}) as List)) r as String];
    return [for (final r in rutas) await urlPrivada(r)];
  }

  Future<List<Adeudo>> adeudos() async => _filas(await _c.rpc('adeudos_listar')).map(Adeudo.desdeMapa).toList();

  Future<Map<String, dynamic>> personaExpediente(String tipo, String id) async =>
      _mapa(await _c.rpc('persona_expediente', params: {'p_tipo': tipo, 'p_id': id}));

  Future<Map<String, dynamic>> expedientePrestamo(String prestamoId) async =>
      _mapa(await _c.rpc('expediente_prestamo', params: {'p_prestamo': prestamoId}));

  Future<void> bloquearSolicitante(String id, String motivo) => _c.rpc('solicitante_bloquear', params: {'p_id': id, 'p_motivo': motivo});

  Future<void> desbloquearSolicitante(String id, String motivo) =>
      _c.rpc('solicitante_desbloquear', params: {'p_id': id, 'p_motivo': motivo});

  Future<void> editarSolicitante(String id, {required String nombre, String? grupo, String? correo, String? telefono}) => _c.rpc(
      'solicitante_editar',
      params: {'p_id': id, 'p_nombre': nombre, 'p_grupo': grupo, 'p_correo': correo, 'p_telefono': telefono});

  // --- Avisos ---------------------------------------------------------------------------------
  Future<List<Aviso>> avisos() async => _filas(await _c.rpc('avisos_listar')).map(Aviso.desdeMapa).toList();

  Future<int> avisosSinLeer() async => await _c.rpc('avisos_sin_leer') as int;

  Future<void> marcarAvisosLeidos() => _c.rpc('avisos_marcar_leidos');

  Future<void> registrarDispositivo(String token) =>
      _c.rpc('dispositivo_registrar', params: {'p_token': token, 'p_plataforma': 'android'});

  // --- Configuración -----------------------------------------------------------------------------
  Future<Map<String, dynamic>> configuracion() async {
    final filas = await _guardadas('configuracion', () => _c.from('configuracion').select('clave, valor'));
    return {for (final f in filas) f['clave'] as String: f['valor']};
  }

  Future<void> cambiarConfiguracion(String clave, Object valor) =>
      _c.rpc('configuracion_cambiar', params: {'p_clave': clave, 'p_valor': valor});

  // --- Contenedores y acomodo (Fase 4a) -----------------------------------------------------
  Future<List<Contenedor>> contenedores() async {
    final filas = await _guardadas('contenedores', () => _c.from('v_contenedores').select().order('nombre', ascending: true));
    return filas.map(Contenedor.desdeMapa).toList();
  }

  Future<String> crearContenedor({
    required String id,
    required String nombre,
    required String tipo,
    String? padreId,
    Categoria? categoria,
    FotoNueva? foto,
    String? nota,
  }) async {
    final ruta = foto == null ? null : await subirFotoContenedor(id, foto);
    final r = await _c.rpc('contenedor_crear', params: {
      'p_id': id,
      'p_nombre': nombre,
      'p_tipo': tipo,
      'p_padre': padreId,
      'p_categoria': categoria?.codigo,
      'p_foto': ruta,
      'p_nota': nota,
    });
    return (r as Map)['codigo'] as String;
  }

  Future<void> editarContenedor(Contenedor actual,
      {required String nombre, required String tipo, String? padreId, Categoria? categoria, FotoNueva? foto, String? nota}) async {
    final ruta = foto == null ? actual.foto : await subirFotoContenedor(actual.id, foto);
    await _c.rpc('contenedor_editar', params: {
      'p_id': actual.id,
      'p_nombre': nombre,
      'p_tipo': tipo,
      'p_padre': padreId,
      'p_categoria': categoria?.codigo,
      'p_foto': ruta,
      'p_nota': nota,
    });
  }

  Future<String> subirFotoContenedor(String id, FotoNueva foto) async {
    if (foto.rutaSubida != null) return foto.rutaSubida!;
    final ruta = 'contenedores/$id/${DateTime.now().toUtc().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
    await _c.storage.from(Configuracion.almacenFotos).uploadBinary(ruta, foto.bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    return foto.rutaSubida = ruta;
  }

  Future<void> activarContenedor(String id, bool activo) => _c.rpc('contenedor_activar', params: {'p_id': id, 'p_activo': activo});

  /// [contenedorId] null = quitar la ubicación. Devuelve cuántos cambiaron de lugar.
  Future<int> acomodar(List<String> articulos, String? contenedorId) async =>
      await _c.rpc('articulos_acomodar', params: {'p_articulos': articulos, 'p_contenedor': contenedorId}) as int;

  Future<void> proponerUbicacion(String articuloId, String contenedorId, String? nota) =>
      _c.rpc('ubicacion_proponer', params: {'p_articulo': articuloId, 'p_contenedor': contenedorId, 'p_nota': nota});

  Future<List<PropuestaUbicacion>> propuestasUbicacion() async =>
      _filas(await _c.rpc('ubicacion_propuestas')).map(PropuestaUbicacion.desdeMapa).toList();

  Future<void> resolverPropuesta(String id, {required bool aceptar, String? motivo}) =>
      _c.rpc('ubicacion_resolver', params: {'p_id': id, 'p_aceptar': aceptar, 'p_motivo': motivo});

  Future<List<PrestamoListado>> prestamosDeContenedor(String contenedorId) async =>
      _filas(await _c.rpc('prestamos_de_contenedor', params: {'p_contenedor': contenedorId})).map(PrestamoListado.desdeMapa).toList();

  /// Varias devoluciones "en buen estado" de una vez (los daños se registran en la devolución de cada artículo).
  Future<void> devolverVarios(Map<String, int> regresanPorPrestamo, String comando) => _c.rpc('devolucion_registrar', params: {
        'p_lineas': [for (final e in regresanPorPrestamo.entries) {'prestamo_id': e.key, 'regresan': e.value}],
        'p_comando': comando,
      });

  // --- Pendientes, conteos, desglose e inventario (Fase 4b) --------------------------------------
  Future<List<PendienteAbierto>> pendientesAbiertos() async {
    final filas = await _guardadas('pendientes_abiertos', () => _c
        .from('tarea_pendiente')
        .select('id, articulo_id, tipo, descripcion, prioridad, creada_en')
        .eq('resuelta', false)
        .order('prioridad', ascending: false)
        .order('creada_en', ascending: true));
    return filas.map(PendienteAbierto.desdeMapa).toList();
  }

  Future<List<AportePendiente>> aportesDePendiente(String tareaId) async =>
      _filas(await _c.rpc('pendiente_aportes', params: {'p_tarea': tareaId})).map(AportePendiente.desdeMapa).toList();

  Future<void> aportarAPendiente(String tareaId, String articuloId, String nota, FotoNueva? foto) async {
    await _oEnCola(() async {
      final ruta = foto == null ? null : await subirFoto(articuloId, foto);
      await _c.rpc('pendiente_aportar', params: {'p_tarea': tareaId, 'p_nota': nota, 'p_foto': ruta});
    }, () {
      final ruta = foto == null ? null : _rutaNueva('articulos/$articuloId');
      return _comando(_uuid.v4(), 'APORTE', {'tarea_id': tareaId, 'nota': nota, 'foto': ruta}, 'Nota en pendiente: ${_nombreArticulo(articuloId)}',
          [articuloId],
          fotos: {if (ruta != null) ruta: (bytes: foto!.bytes, bucket: Configuracion.almacenFotos)});
    });
  }

  Future<void> resolverPendiente(String tareaId, Map<String, dynamic> datos) =>
      _c.rpc('pendiente_resolver', params: {'p_tarea': tareaId, 'p_datos': datos});

  /// Sube la foto de la placa a la carpeta del artículo (se usa al resolver "registrar serie").
  Future<String> subirFotoArticulo(String articuloId, FotoNueva foto) => subirFoto(articuloId, foto);

  Future<({int sistema, int diferencia})> proponerConteo(String articuloId, int enTaller, String? nota) async {
    Map<String, dynamic>? m;
    await _oEnCola(() async {
      m = _mapa(await _c.rpc('conteo_proponer', params: {'p_articulo': articuloId, 'p_en_taller': enTaller, 'p_nota': nota}));
    }, () => _comando(_uuid.v4(), 'CONTEO', {'articulo_id': articuloId, 'en_taller': enTaller, 'nota': nota},
        'Conteo: ${_nombreArticulo(articuloId)} = $enTaller', [articuloId]));
    if (m != null) return (sistema: m!['sistema'] as int, diferencia: m!['diferencia'] as int);
    final a = _cola?.leerFilas('articulos')?.where((x) => x['id'] == articuloId).firstOrNull;
    final sistema = a == null ? enTaller : (a['existencia'] as int) - (a['prestado'] as int) - (a['fuera_servicio'] as int);
    return (sistema: sistema, diferencia: enTaller - sistema);
  }

  Future<List<ConteoPorAplicar>> conteosPorAplicar() async =>
      _filas(await _c.rpc('conteos_por_aplicar')).map(ConteoPorAplicar.desdeMapa).toList();

  Future<({int aplicados, int ajustes})> aplicarConteos(List<String> ids, Map<String, String> notas) async {
    final m = _mapa(await _c.rpc('conteos_aplicar', params: {'p_ids': ids, 'p_notas': notas}));
    return (aplicados: m['aplicados'] as int, ajustes: m['ajustes'] as int);
  }

  Future<void> descartarConteos(List<String> ids, String motivo) =>
      _c.rpc('conteos_descartar', params: {'p_ids': ids, 'p_motivo': motivo});

  Future<List<PlantillaKit>> plantillasKit() async {
    final filas = await _c.from('plantilla_kit').select('id, nombre, sku, categoria, nota').eq('activa', true).order('nombre', ascending: true);
    return filas.map(PlantillaKit.desdeMapa).toList();
  }

  Future<Desglose> iniciarDesglose(String articuloId, int unidades, String? plantillaId) async => Desglose.desdeMapa(
      _mapa(await _c.rpc('desglose_iniciar', params: {'p_articulo': articuloId, 'p_unidades': unidades, 'p_plantilla': plantillaId})));

  Future<Desglose> guardarDesglose(Desglose d) async => Desglose.desdeMapa(_mapa(await _c.rpc('desglose_guardar', params: {
        'p_id': d.id,
        'p_unidades': d.unidades,
        'p_lineas': [for (final l in d.lineas) l.aMapa()],
        'p_nota': d.nota,
      })));

  Future<List<Map<String, dynamic>>> desglosesDeArticulo(String articuloId) async =>
      _filas(await _c.rpc('desgloses_de_articulo', params: {'p_articulo': articuloId}));

  Future<Desglose> detalleDesglose(String id) async => Desglose.desdeMapa(_mapa(await _c.rpc('desglose_detalle', params: {'p_id': id})));

  Future<({int creados, int sumados, int faltantes})> terminarDesglose(String id, String destino) async {
    final m = _mapa(await _c.rpc('desglose_terminar', params: {'p_id': id, 'p_destino': destino}));
    return (creados: m['creados'] as int, sumados: m['sumados'] as int, faltantes: m['faltantes'] as int);
  }

  Future<void> cancelarDesglose(String id) => _c.rpc('desglose_cancelar', params: {'p_id': id});

  Future<List<InventarioResumen>> inventarios() async =>
      (await _guardadas('inventarios', () => _c.rpc('inventarios_listar'))).map(InventarioResumen.desdeMapa).toList();

  Future<String> abrirInventario(String nombre, Map<String, dynamic> alcance) async =>
      await _c.rpc('inventario_abrir', params: {'p_nombre': nombre, 'p_alcance': alcance}) as String;

  Future<List<ArticuloDeInventario>> articulosDeInventario(String id) async =>
      (await _guardadas('inventario_$id', () => _c.rpc('inventario_articulos', params: {'p_inventario': id})))
          .map(ArticuloDeInventario.desdeMapa)
          .toList();

  Future<void> contarEnInventario(String id, String articuloId, int cantidad, {String? contenedorId, String? nota}) => _oEnCola(
      () async => _c.rpc('inventario_contar',
          params: {'p_inventario': id, 'p_articulo': articuloId, 'p_cantidad': cantidad, 'p_contenedor': contenedorId, 'p_nota': nota}),
      () => _comando(_uuid.v4(), 'CONTEO_INVENTARIO',
          {'inventario_id': id, 'articulo_id': articuloId, 'cantidad': cantidad, 'contenedor_id': contenedorId, 'nota': nota},
          'Conteo de inventario: ${_nombreArticulo(articuloId)} = $cantidad', [articuloId]));

  Future<void> registrarHallazgo(String id, String descripcion, {String? contenedorId, String? articuloId, int? cantidad, FotoNueva? foto}) async {
    String? ruta;
    if (foto != null) {
      ruta = foto.rutaSubida ??
          'inventarios/$id/${DateTime.now().toUtc().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';
      if (foto.rutaSubida == null) {
        await _c.storage.from(Configuracion.almacenFotos).uploadBinary(ruta, foto.bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
        foto.rutaSubida = ruta;
      }
    }
    await _c.rpc('inventario_hallazgo_registrar', params: {
      'p_inventario': id,
      'p_descripcion': descripcion,
      'p_contenedor': contenedorId,
      'p_articulo': articuloId,
      'p_cantidad': cantidad,
      'p_foto': ruta,
    });
  }

  Future<List<DiferenciaInventario>> diferenciasDeInventario(String id) async =>
      _filas(await _c.rpc('inventario_diferencias', params: {'p_inventario': id})).map(DiferenciaInventario.desdeMapa).toList();

  Future<void> decidirEnInventario(String id, String articuloId, String decision, String? nota) => _c.rpc('inventario_decidir',
      params: {'p_inventario': id, 'p_articulo': articuloId, 'p_decision': decision, 'p_nota': nota});

  Future<List<Hallazgo>> hallazgosDeInventario(String id) async =>
      _filas(await _c.rpc('inventario_hallazgos', params: {'p_inventario': id})).map(Hallazgo.desdeMapa).toList();

  Future<void> resolverHallazgo(String id, String decision, String? nota) =>
      _c.rpc('inventario_hallazgo_resolver', params: {'p_id': id, 'p_decision': decision, 'p_nota': nota});

  Future<Map<String, dynamic>> cerrarInventario(String id) async => _mapa(await _c.rpc('inventario_cerrar', params: {'p_inventario': id}));

  // --- Fase 5: reportes (se arman en el dispositivo) --------------------------------
  static String _dia(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> encabezadoReporte() async => _mapa(await _c.rpc('reporte_encabezado'));

  Future<List<Map<String, dynamic>>> reportePrestamosAbiertos() async => _filas(await _c.rpc('reporte_prestamos_abiertos'));

  Future<List<Map<String, dynamic>>> reporteIncidencias(DateTime desde, DateTime hasta) async =>
      _filas(await _c.rpc('reporte_incidencias', params: {'p_desde': _dia(desde), 'p_hasta': _dia(hasta)}));

  Future<List<Map<String, dynamic>>> reporteBajas(DateTime desde, DateTime hasta) async =>
      _filas(await _c.rpc('reporte_bajas', params: {'p_desde': _dia(desde), 'p_hasta': _dia(hasta)}));

  Future<List<Map<String, dynamic>>> reporteMovimientos(DateTime desde, DateTime hasta) async =>
      _filas(await _c.rpc('reporte_movimientos', params: {'p_desde': _dia(desde), 'p_hasta': _dia(hasta)}));

  Future<List<Map<String, dynamic>>> reporteFaltantesKits() async => _filas(await _c.rpc('reporte_faltantes_kits'));

  Future<Map<String, dynamic>> reporteInventarioPeriodico(String id) async =>
      _mapa(await _c.rpc('reporte_inventario_periodico', params: {'p_inventario': id}));

  /// Deja constancia en la bitácora; las actas regresan su folio.
  Future<String?> registrarReporte(String tipo, String formato, Map<String, dynamic> parametros) async =>
      await _c.rpc('reporte_registrar', params: {'p_tipo': tipo, 'p_formato': formato, 'p_parametros': parametros}) as String?;

  Future<List<Map<String, dynamic>>> revisionesKit() async => _filas(await _c.rpc('revisiones_kit'));

  Future<Map<String, dynamic>> crearRevisionKit(String plantillaId, int kits, String? nombre) async => _mapa(
      await _c.rpc('revision_kit_crear', params: {'p_plantilla': plantillaId, 'p_kits': kits, 'p_nombre': nombre, 'p_articulo': null}));

  Future<Map<String, dynamic>> detalleRevisionKit(String id) async => _mapa(await _c.rpc('revision_kit_detalle', params: {'p_id': id}));

  Future<Map<String, dynamic>> guardarRevisionKit(String id, int kits, List<Map<String, dynamic>> lineas, String? nota) async =>
      _mapa(await _c.rpc('revision_kit_guardar', params: {'p_id': id, 'p_kits': kits, 'p_lineas': lineas, 'p_nota': nota}));

  /// "Avísame cuando regrese": por la función pública (freno por red).
  Future<String> avisarmeCuandoRegrese(String articuloId, String correo, String dispositivo) async {
    final r = await _c.functions.invoke('solicitud-publica',
        body: {'accion': 'avisarme', 'articulo_id': articuloId, 'correo': correo, 'dispositivo': dispositivo});
    final m = _mapa(r.data);
    if (m['ok'] != true) throw ErrorApp(m['mensaje'] as String? ?? 'No se pudo registrar el aviso.');
    return m['mensaje'] as String;
  }

  // --- Fase 6: sin conexión (solo en el celular) -------------------------------------
  Future<List<Map<String, dynamic>>> conflictosSinConexion() async => _filas(await _c.rpc('conflictos_sin_conexion'));

  ColaSinConexion? get _cola => ColaSinConexion.instancia;

  /// Lee del servidor y guarda una copia; sin señal regresa la copia.
  Future<List<Map<String, dynamic>>> _guardadas(String nombre, Future<Object?> Function() leer) async {
    try {
      final filas = _filas(await leer());
      await _cola?.guardarCache(nombre, filas);
      return filas;
    } on Object catch (e) {
      final copia = _deCopia(e, nombre);
      if (copia == null) rethrow;
      return copia;
    }
  }

  List<Map<String, dynamic>>? _deCopia(Object error, String nombre) =>
      _cola == null || !esFaltaDeConexion(error) ? null : _cola!.leerFilas(nombre);

  /// Intenta con el servidor; si no hay señal, lo deja en la cola. Devuelve true si se hizo en línea.
  Future<bool> _oEnCola(Future<void> Function() enLinea, Future<ComandoArmado> Function() armar) async {
    try {
      await enLinea().timeout(Duration(seconds: (_cola?.sinSenal ?? false) ? 12 : 30));
      return true;
    } on Object catch (e) {
      if (_cola == null || !esFaltaDeConexion(e) || _c.auth.currentUser == null) rethrow;
      final armado = await armar();
      await _cola!.agregar(armado.comando, fotos: armado.fotos);
      return false;
    }
  }

  Future<ComandoArmado> _comando(String id, String tipo, Map<String, dynamic> datos, String resumen, List<String> articulos,
      {Map<String, FotoPorSubir> fotos = const {}, Map<String, ({int existencia, int prestado})> estimar = const {}}) async {
    final sesion = _cola?.leerCache('sesion');
    for (final e in estimar.entries) {
      await _estimar(e.key, existencia: e.value.existencia, prestado: e.value.prestado);
    }
    return (
      comando: Comando(
        id: id,
        tipo: tipo,
        datos: datos,
        capturado: DateTime.now(),
        usuarioId: _c.auth.currentUser!.id,
        usuarioNombre: sesion is Map ? '${sesion['nombre']}' : 'la misma cuenta',
        resumen: resumen,
        articuloIds: articulos,
      ),
      fotos: fotos,
    );
  }

  /// Cifra provisional en la copia del catálogo mientras lo capturado no llega al servidor.
  Future<void> _estimar(String articuloId, {required int existencia, required int prestado}) async {
    final filas = _cola?.leerFilas('articulos');
    final m = filas?.where((x) => x['id'] == articuloId).firstOrNull;
    if (filas == null || m == null) return;
    m['existencia'] = (m['existencia'] as int? ?? 0) + existencia;
    m['prestado'] = (m['prestado'] as int? ?? 0) + prestado;
    for (final campo in ['en_taller', 'disponible']) {
      if (m[campo] is int) m[campo] = (m[campo] as int) + existencia - prestado;
    }
    await _cola!.guardarCache('articulos', filas);
  }

  String _nombreArticulo(String id) => '${_cola?.leerFilas('articulos')?.where((m) => m['id'] == id).firstOrNull?['nombre'] ?? 'artículo'}';

  String _nombres(List<({String articuloId, int cantidad})> lineas) =>
      lineas.map((l) => '${_nombreArticulo(l.articuloId)} ×${l.cantidad}').join(', ');

  String _nombreSolicitante(String id) =>
      '${_cola?.leerFilas('solicitantes')?.where((m) => m['id'] == id).firstOrNull?['nombre_completo'] ?? 'alumno o maestro'}';

  String _rutaNueva(String carpeta) => '$carpeta/${DateTime.now().toUtc().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.jpg';

  String _guardarFotoPrivada(Map<String, FotoPorSubir> guardadas, String incidencia, FotoNueva f) {
    final ruta = _rutaNueva('incidencias/$incidencia');
    guardadas[ruta] = (bytes: f.bytes, bucket: 'privado');
    return ruta;
  }

  /// Hoy a la hora de fin de jornada (o mañana, si ya pasó), como lo calcula el servidor.
  DateTime _finJornada() {
    final config = _cola?.leerFilas('configuracion');
    final valor = '${config?.where((m) => m['clave'] == 'hora_fin_jornada').firstOrNull?['valor'] ?? '15:00'}'.split(':');
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day, int.tryParse(valor.first) ?? 15, int.tryParse(valor.last) ?? 0);
    return hoy.isAfter(ahora) ? hoy : hoy.add(const Duration(days: 1));
  }

  /// Todo lo que el celular necesita para trabajar sin señal.
  Future<void> descargarParaSinConexion() async {
    if (_cola == null) return;
    final lista = await articulos();
    await contenedores();
    await pendientesAbiertos();
    await configuracion();
    await personasConPin();
    if (hayToken && await miSesion() != null) {
      await _cola!.guardarCache('prestamos', _filas(await _c.rpc('prestamos_para_sin_conexion')));
      await _cola!.guardarCache('solicitantes', _filas(await _c.rpc('solicitantes_para_sin_conexion')));
      for (final i in (await inventarios()).where((i) => i.abierto)) {
        await articulosDeInventario(i.id);
      }
    }
    await _cola!.guardarMiniaturas({for (final a in lista) if (a.fotoPrincipal != null) a.fotoPrincipal!: urlFoto(a.fotoPrincipal!)});
  }
}

typedef FotoPorSubir = ({Uint8List bytes, String bucket});
typedef ComandoArmado = ({Comando comando, Map<String, FotoPorSubir> fotos});
