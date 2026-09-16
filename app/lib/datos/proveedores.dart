import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acceso/sesion.dart';
import '../modelos/articulo.dart';
import '../modelos/otros.dart';
import 'repositorio.dart';

/// El catálogo completo. Son pocos cientos de renglones: se baja una vez y se filtra en el dispositivo.
final articulosProvider = FutureProvider<List<Articulo>>((ref) => ref.watch(repositorioProvider).articulos());

final articuloProvider = FutureProvider.family<Articulo?, String>((ref, id) => ref.watch(repositorioProvider).articulo(id));

final fotosProvider = FutureProvider.family<List<Foto>, String>((ref, id) => ref.watch(repositorioProvider).fotos(id));

final historialProvider =
    FutureProvider.family<List<MovimientoPublico>, String>((ref, id) => ref.watch(repositorioProvider).historial(id));

final pendientesProvider =
    FutureProvider.family<List<Pendiente>, String>((ref, id) => ref.watch(repositorioProvider).pendientes(id));

/// La sesión según el servidor. Si la jornada ya terminó, se cierra aquí mismo.
final sesionProvider = FutureProvider<Sesion?>((ref) async {
  final repo = ref.watch(repositorioProvider);
  final sesion = await repo.miSesion();
  if (repo.hayToken && (sesion == null || !sesion.vigente || !sesion.activo)) {
    await repo.salir();
    return null;
  }
  return sesion;
});

/// Después de cambiar algo de un artículo, se vuelve a leer todo lo que lo muestra.
void refrescarArticulo(WidgetRef ref, String id) {
  ref.invalidate(articulosProvider);
  ref.invalidate(articuloProvider(id));
  ref.invalidate(fotosProvider(id));
  ref.invalidate(historialProvider(id));
  ref.invalidate(pendientesProvider(id));
}
