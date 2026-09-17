import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../acceso/sesion.dart';
import '../configuracion.dart';
import '../modelos/articulo.dart';
import '../modelos/catalogos.dart';
import '../modelos/movimientos.dart';
import '../modelos/otros.dart';
import '../modelos/solicitudes.dart';
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
    final filas = await _c
        .from('v_inventario')
        .select()
        .eq('activo', true)
        // En el cliente de Dart, order() es descendente si no se indica.
        .order('categoria', ascending: true)
        .order('ref_foto', ascending: true, nullsFirst: false)
        .order('nombre', ascending: true);
    return filas.map(Articulo.desdeMapa).toList();
  }

  Future<Articulo?> articulo(String id) async {
    final fila = await _c.from('v_inventario').select().eq('id', id).maybeSingle();
    return fila == null ? null : Articulo.desdeMapa(fila);
  }

  Future<String?> idPorCodigo(String codigo) async {
    final fila = await _c.from('v_inventario').select('id').eq('codigo', codigo.toUpperCase()).maybeSingle();
    return fila?['id'] as String?;
  }

  Future<List<Foto>> fotos(String articuloId) async {
    final filas = await _c
        .from('foto')
        .select('id, url, es_principal, tipo, tomada_en')
        .eq('articulo_id', articuloId)
        .order('es_principal', ascending: false)
        .order('tomada_en', ascending: false);
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
    final filas = await _c
        .from('v_historial_publico')
        .select()
        .eq('articulo_id', articuloId)
        .order('fecha', ascending: false)
        .limit(100);
    return filas.map(MovimientoPublico.desdeMapa).toList();
  }

  Future<List<Pendiente>> pendientes(String articuloId) async {
    final filas = await _c
        .from('tarea_pendiente')
        .select('tipo, descripcion, prioridad')
        .eq('articulo_id', articuloId)
        .eq('resuelta', false)
        .order('prioridad', ascending: false);
    return filas.map(Pendiente.desdeMapa).toList();
  }

  String urlFoto(String ruta) => _c.storage.from(Configuracion.almacenFotos).getPublicUrl(ruta);

  // --- Sesión -------------------------------------------------------------------
  bool get hayToken => _c.auth.currentSession != null;

  Future<Sesion?> miSesion() async {
    if (!hayToken) return null;
    final r = await _c.rpc('mi_sesion');
    return Sesion.desdeMapa(r == null ? null : Map<String, dynamic>.from(r as Map));
  }

  Future<List<PersonaPin>> personasConPin() async {
    final filas = await _c.rpc('pin_usuarios') as List<dynamic>;
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

  /// F-07. Devuelve el grupo del préstamo (para deshacer).
  Future<String> prestar({
    required List<({String articuloId, int cantidad})> lineas,
    required String comando,
    String? responsableUsuario,
    String? responsableSolicitante,
    DateTime? fechaCompromiso,
    String? nota,
  }) async {
    final r = await _c.rpc('prestamo_registrar', params: {
      'p_lineas': [for (final l in lineas) {'articulo_id': l.articuloId, 'cantidad': l.cantidad}],
      'p_responsable_usuario': responsableUsuario,
      'p_responsable_solicitante': responsableSolicitante,
      'p_fecha_compromiso': fechaCompromiso?.toUtc().toIso8601String(),
      'p_nota': nota,
      'p_comando': comando,
    });
    return (r as Map)['grupo'] as String;
  }

  Future<void> deshacerPrestamo(String grupo) => _c.rpc('prestamo_deshacer', params: {'p_grupo': grupo});

  Future<void> extenderPrestamo(String prestamoId, DateTime fecha, String motivo) => _c.rpc('prestamo_extender',
      params: {'p_prestamo': prestamoId, 'p_fecha': fecha.toUtc().toIso8601String(), 'p_motivo': motivo});

  Future<List<PrestamoAbierto>> prestamosDeArticulo(String articuloId) async =>
      _filas(await _c.rpc('prestamos_de_articulo', params: {'p_articulo': articuloId})).map(PrestamoAbierto.desdeMapa).toList();

  Future<List<PrestamoListado>> misPrestamos() async => _filas(await _c.rpc('mis_prestamos')).map(PrestamoListado.desdeMapa).toList();

  Future<List<PrestamoListado>> prestamosAbiertos() async =>
      _filas(await _c.rpc('prestamos_abiertos_listar')).map(PrestamoListado.desdeMapa).toList();

  Future<List<SolicitanteEncontrado>> buscarSolicitante(String matricula) async =>
      _filas(await _c.rpc('solicitante_buscar', params: {'p_matricula': matricula})).map(SolicitanteEncontrado.desdeMapa).toList();

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
    final linea = <String, dynamic>{'prestamo_id': prestamoId, 'regresan': regresan, 'danadas': danadas};
    if (danadas > 0) {
      linea.addAll({
        'incidencia_dano_id': incidenciaDanoId,
        'nota_dano': notaDano,
        'fotos_dano': await subirFotosPrivadas(incidenciaDanoId!, fotosDano),
      });
    }
    if (faltantePerdido) {
      linea.addAll({
        'faltante': 'PERDIDO',
        'incidencia_perdida_id': incidenciaPerdidaId,
        'nota_perdida': notaPerdida,
        'fotos_perdida': await subirFotosPrivadas(incidenciaPerdidaId!, fotosPerdida),
        'sin_foto_perdida': sinFotoPerdida,
      });
    }
    await _c.rpc('devolucion_registrar', params: {'p_lineas': [linea], 'p_comando': comando});
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
  }

  /// F-10. Devuelve true si se aplicó; false si quedó por autorizar.
  Future<bool> registrarUso(String articuloId, int cantidad, String? nota, String comando) async {
    final r = await _c.rpc('consumo_registrar',
        params: {'p_articulo': articuloId, 'p_cantidad': cantidad, 'p_nota': nota, 'p_comando': comando});
    return (r as Map)['aplicado'] as bool;
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
    final filas = await _c.from('configuracion').select('clave, valor');
    return {for (final f in filas) f['clave'] as String: f['valor']};
  }

  Future<void> cambiarConfiguracion(String clave, Object valor) =>
      _c.rpc('configuracion_cambiar', params: {'p_clave': clave, 'p_valor': valor});
}
