import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../modelos/articulo.dart';
import '../modelos/solicitudes.dart';

/// Lo que se guarda solo en este dispositivo: "Mi solicitud" (carrito), los enlaces a solicitudes
/// enviadas y un identificador del dispositivo para el freno contra abusos. Nunca datos personales.
abstract final class AlmacenLocal {
  static const _carrito = 'carrito';
  static const _carritoEn = 'carrito_en';
  static const _guardadas = 'solicitudes_guardadas';
  static const _dispositivo = 'dispositivo';

  /// El carrito se olvida solo después de un día (F-04: "se arrepiente mientras llena el formulario").
  static const vigenciaCarrito = Duration(hours: 24);

  static Future<String> dispositivo() async {
    final p = await SharedPreferences.getInstance();
    final actual = p.getString(_dispositivo);
    if (actual != null) return actual;
    final nuevo = const Uuid().v4();
    await p.setString(_dispositivo, nuevo);
    return nuevo;
  }

  static Future<List<LineaCarrito>> leerCarrito() async {
    final p = await SharedPreferences.getInstance();
    final en = DateTime.tryParse(p.getString(_carritoEn) ?? '');
    if (en == null || DateTime.now().difference(en) > vigenciaCarrito) return [];
    final crudo = p.getString(_carrito);
    if (crudo == null) return [];
    return [for (final m in jsonDecode(crudo) as List) LineaCarrito.desdeMapa(Map<String, dynamic>.from(m as Map))];
  }

  static Future<void> guardarCarrito(List<LineaCarrito> lineas) async {
    final p = await SharedPreferences.getInstance();
    if (lineas.isEmpty) {
      await p.remove(_carrito);
      await p.remove(_carritoEn);
      return;
    }
    await p.setString(_carrito, jsonEncode([for (final l in lineas) l.aMapa()]));
    await p.setString(_carritoEn, DateTime.now().toIso8601String());
  }

  static Future<List<SolicitudGuardada>> solicitudes() async {
    final p = await SharedPreferences.getInstance();
    final crudo = p.getString(_guardadas);
    if (crudo == null) return [];
    return [for (final m in jsonDecode(crudo) as List) SolicitudGuardada.desdeMapa(Map<String, dynamic>.from(m as Map))];
  }

  static Future<void> guardarSolicitud(SolicitudGuardada s) async {
    final lista = (await solicitudes()).where((x) => x.token != s.token && x.folio != s.folio).toList()..insert(0, s);
    await _escribir(lista.take(30).toList());
  }

  static Future<void> olvidarSolicitud(String token) async => _escribir((await solicitudes()).where((x) => x.token != token).toList());

  static Future<void> _escribir(List<SolicitudGuardada> lista) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_guardadas, jsonEncode([for (final s in lista) s.aMapa()]));
  }
}

/// "Mi solicitud": los artículos que alguien sin cuenta va juntando antes de pedir.
class Carrito extends Notifier<List<LineaCarrito>> {
  @override
  List<LineaCarrito> build() {
    AlmacenLocal.leerCarrito().then((lineas) {
      if (lineas.isNotEmpty && state.isEmpty) state = lineas;
    });
    return const [];
  }

  void agregar(Articulo a) {
    if (state.any((l) => l.articuloId == a.id)) return;
    _poner([...state, LineaCarrito(articuloId: a.id, codigo: a.codigo, nombre: a.nombre, unidad: a.unidad, foto: a.fotoPrincipal, cantidad: 1)]);
  }

  void cambiarCantidad(String articuloId, int cantidad) =>
      _poner([for (final l in state) l.articuloId == articuloId ? (l..cantidad = cantidad) : l]);

  void quitar(String articuloId) => _poner(state.where((l) => l.articuloId != articuloId).toList());

  void vaciar() => _poner(const []);

  void _poner(List<LineaCarrito> lineas) {
    state = lineas;
    AlmacenLocal.guardarCarrito(lineas);
  }
}

final carritoProvider = NotifierProvider<Carrito, List<LineaCarrito>>(Carrito.new);

final solicitudesGuardadasProvider = FutureProvider<List<SolicitudGuardada>>((ref) => AlmacenLocal.solicitudes());
