import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../acceso/sesion.dart';
import '../configuracion.dart';
import '../modelos/articulo.dart';
import '../modelos/catalogos.dart';
import '../modelos/otros.dart';
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
}
